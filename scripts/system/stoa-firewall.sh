#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Firewall & Port Monitor                      ║
# ║  "A city without walls is a city already conquered."        ║
# ║   — Marcus Aurelius                                         ║
# ║                                                              ║
# ║  nftables firewall: all ports closed by default.             ║
# ║  Port monitor: notify-send/noctalia toast when apps open    ║
# ║  ports, with inline allow/deny actions.                     ║
# ╚══════════════════════════════════════════════════════════════╝
#
# USAGE:
#   stoa-firewall setup     — Install nftables and configure deny-all
#   stoa-firewall status    — Show firewall status and rules
#   stoa-firewall ports     — Show all ports, status, and processes
#   stoa-firewall allow     — Allow a port (add to whitelist)
#   stoa-firewall deny      — Block a port (remove from whitelist)
#   stoa-firewall enable    — Enable firewall
#   stoa-firewall disable   — Disable firewall
#   stoa-firewall monitor   — Start port monitor daemon (background)
#   stoa-firewall authorize — Authorize a port from notification

# ── Colors ──
# ── --help ──
case "${1:-}" in
    -h|--help|help)
        cat <<'STOA_HELP'
stoa-firewall — nftables firewall (deny all inbound) with a port monitor.

USAGE
  stoa-firewall [COMMAND [ARGS]]      default command: status

COMMANDS
  setup                   install nftables and configure deny-all
  status                  firewall status and the active rules
  ports                   every listening port, whether it is allowed, and the process
  allow PORT [tcp|udp]    add a port to the whitelist (default: tcp)
  deny PORT [tcp|udp]     remove a port from the whitelist
  authorize PORT [tcp|udp]  allow a port permanently without checks; used by the monitor's
                          notification action
  enable                  enable nftables at boot
  disable                 disable it
  active                  exit 0 if the firewall is loaded (never asks for a password)
  monitor                 watch for new listening ports and notify, with allow/deny actions
                          (run as a systemd user service)
  help                    show this help

OPTIONS
  -h, --help    show this help

RESUMO RÁPIDO
  stoa-firewall [status]
  stoa-firewall setup | ports | enable | disable | monitor
  stoa-firewall allow PORT [tcp|udp]
  stoa-firewall deny PORT [tcp|udp]
  stoa-firewall authorize PORT [tcp|udp]
  stoa-firewall -h | --help | help
STOA_HELP
        exit 0
        ;;
esac

B='\033[38;2;196;154;92m'
S='\033[38;2;110;106;98m'
F='\033[38;2;212;207;196m'
O='\033[38;2;138;154;108m'
T='\033[38;2;179;107;90m'
R='\033[0m'

STOA_FW_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/firewall"
WHITELIST="${STOA_FW_DIR}/allowed-ports.conf"
KNOWN_PORTS="${STOA_FW_DIR}/known-ports.list"
NFT_RULES="/etc/nftables.d/stoa-firewall.conf"

_banner() {
    echo ""
    echo -e "  ${B}╔══════════════════════════════════════════╗${R}"
    echo -e "  ${B}║     STOA — Firewall & Ports              ║${R}"
    echo -e "  ${B}╚══════════════════════════════════════════╝${R}"
    echo ""
}

_notify() {
    notify-send -t 3000 "Stoa Firewall" "$1" 2>/dev/null
}

# Root for the nft and systemctl calls. The script also runs from the settings
# panel and the port monitor, with no terminal: a bare sudo cannot ask there and
# pam_faillock counts the failure. Cached/NOPASSWD sudo, else polkit's prompt.
_priv() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif sudo -n true 2>/dev/null; then
        sudo -n "$@"
    elif command -v pkexec >/dev/null 2>&1; then
        pkexec "$@"
    else
        echo -e "  ${T}[!] Needs root and no terminal or polkit agent is available.${R}" >&2
        return 1
    fi
}

# Every _priv that has to go through pkexec is its own password box, so root
# work is never spread over several calls: it is gathered into ONE script and
# sent through _priv once (see _ROOT_APPLY and cmd_disable). Read-only checks
# must never prompt at all — _fw_active.
_fw_active() {
    local out
    if [ "$(id -u)" -eq 0 ]; then
        nft list table inet stoa_firewall &>/dev/null
    elif sudo -n true 2>/dev/null; then
        sudo -n nft list table inet stoa_firewall &>/dev/null
    else
        # No root without asking: the rules file is world-readable, and
        # nftables.service reloads it at boot and on enable.
        [ -s "$NFT_RULES" ] && systemctl is-active --quiet nftables
    fi
}

_init_dirs() {
    mkdir -p "$STOA_FW_DIR"
    touch "$WHITELIST" "$KNOWN_PORTS"
}

# ── Validate port (1-65535) and protocol (tcp|udp) ──
# Refuses anything that could land unsanitized in nft rules or sed -i patterns.
_validate_port_proto() {
    local port="$1" proto="$2"
    if ! [[ "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
        echo -e "  ${T}[!] Invalid port: ${port} (must be 1-65535).${R}" >&2
        return 1
    fi
    if [[ "$proto" != "tcp" && "$proto" != "udp" ]]; then
        echo -e "  ${T}[!] Invalid protocol: ${proto} (must be tcp or udp).${R}" >&2
        return 1
    fi
    return 0
}

# ── Check if port is in whitelist ──
_is_allowed() {
    local port="$1" proto="${2:-tcp}"
    grep -qx "${port}/${proto}" "$WHITELIST" 2>/dev/null
}

# ── Generate nftables rules from whitelist ──
_generate_rules() {
    local rules=""
    rules+="table inet stoa_firewall {\n"
    rules+="    chain input {\n"
    rules+="        type filter hook input priority 0; policy drop;\n"
    rules+="\n"
    rules+="        # Allow established/related connections\n"
    rules+="        ct state established,related accept\n"
    rules+="\n"
    rules+="        # Allow loopback\n"
    rules+="        iif lo accept\n"
    rules+="\n"
    rules+="        # Allow ICMP (ping)\n"
    rules+="        ip protocol icmp accept\n"
    rules+="        ip6 nexthdr icmpv6 accept\n"
    rules+="\n"
    rules+="        # Allow DHCP client\n"
    rules+="        udp dport 68 accept\n"

    # Add whitelisted ports
    if [ -s "$WHITELIST" ]; then
        rules+="\n"
        rules+="        # Whitelisted ports\n"
        while IFS= read -r entry; do
            [ -z "$entry" ] && continue
            [[ "$entry" == \#* ]] && continue
            local port proto
            port=$(echo "$entry" | cut -d/ -f1)
            proto=$(echo "$entry" | cut -d/ -f2)
            rules+="        ${proto} dport ${port} accept\n"
        done < "$WHITELIST"
    fi

    rules+="\n"
    rules+="        # Log dropped packets (rate-limited)\n"
    rules+="        limit rate 5/minute log prefix \"stoa-fw-drop: \" level warn\n"
    rules+="    }\n"
    rules+="\n"
    rules+="    chain output {\n"
    rules+="        type filter hook output priority 0; policy accept;\n"
    rules+="    }\n"
    rules+="}\n"

    echo -e "$rules"
}

# ── Apply rules ──
# All of the root work, run as ONE privileged call (one password prompt).
# $1 ruleset file (user-owned)   $2 persistent path
# $3 1 = enable nftables.service  $4 1 = make nftables.conf include nftables.d
# Exit: 0 ok, 2 could not stage, 3 ruleset failed validation (old one kept),
#       4 nft -f failed after validation.
_ROOT_APPLY='
src=$1 dest=$2 enable=$3 inc=$4
mkdir -p "$(dirname "$dest")" || exit 2
staged="$dest.new"
# Copy into a root-owned file first: what is validated is what is loaded, and
# the user-owned temp file cannot be swapped in between.
install -m 0644 -o root -g root "$src" "$staged" || exit 2
# Dry-run BEFORE flushing the old table. Without this, a syntax error leaves
# the firewall fully open.
if ! nft -c -f "$staged" 2>/dev/null; then rm -f "$staged"; exit 3; fi
[ "$enable" = 1 ] && systemctl enable nftables --now >/dev/null 2>&1
if [ "$inc" = 1 ] && ! grep -q "include.*nftables.d" /etc/nftables.conf 2>/dev/null; then
    echo "include \"/etc/nftables.d/*.conf\"" >> /etc/nftables.conf
fi
nft delete table inet stoa_firewall 2>/dev/null
if ! nft -f "$staged"; then rm -f "$staged"; exit 4; fi
mv -f "$staged" "$dest"
'

# _apply_rules [--enable-service] [--ensure-include]
_apply_rules() {
    local enable=0 inc=0 arg tmpfile rc
    for arg in "$@"; do
        case "$arg" in
            --enable-service) enable=1 ;;
            --ensure-include) inc=1 ;;
        esac
    done
    tmpfile=$(mktemp)
    _generate_rules > "$tmpfile"
    chmod 0644 "$tmpfile"

    _priv bash -c "$_ROOT_APPLY" stoa-root "$tmpfile" "$NFT_RULES" "$enable" "$inc"
    rc=$?
    rm -f "$tmpfile"
    case "$rc" in
        0) return 0 ;;
        3) echo -e "  ${T}[!] Generated nftables ruleset failed validation; keeping previous ruleset.${R}" >&2 ;;
        4) echo -e "  ${T}[!] nft -f failed unexpectedly after validation; firewall may be inactive.${R}" >&2 ;;
        *) echo -e "  ${T}[!] Could not apply the firewall rules (no administrator access?).${R}" >&2 ;;
    esac
    return 1
}

# ══════════════════════════════════════════════════════════════
#   COMMANDS
# ══════════════════════════════════════════════════════════════

cmd_setup() {
    _banner
    _init_dirs

    echo -e "  ${F}Setting up Stoa Firewall (nftables)...${R}"
    echo ""

    # Check nftables
    if ! command -v nft &>/dev/null; then
        echo -e "  ${T}[!] nftables not installed.${R}"
        echo -e "  ${S}    sudo pacman -S nftables${R}"
        exit 1
    fi

    # Service, include directive and deny-all rules: one privileged call.
    echo -e "  ${S}  Enabling nftables and applying deny-all policy...${R}"
    _apply_rules --enable-service --ensure-include || exit 1

    # Install and enable port monitor
    echo -e "  ${S}  Installing port monitor service...${R}"
    _install_monitor_service

    echo ""
    echo -e "  ${O}[✓] Firewall active. All incoming ports blocked.${R}"
    echo -e "  ${O}[✓] Port monitor running. You'll be notified of new ports.${R}"
    echo -e "  ${S}    Manage via: Super+S → Firewall${R}"
    echo ""
}

cmd_status() {
    _banner

    if _fw_active; then
        echo -e "  ${O}  Status: ACTIVE${R}"
    else
        echo -e "  ${T}  Status: INACTIVE${R}"
    fi
    echo ""

    # Show whitelisted ports
    if [ -s "$WHITELIST" ]; then
        echo -e "  ${F}  Allowed ports:${R}"
        while IFS= read -r entry; do
            [ -z "$entry" ] && continue
            [[ "$entry" == \#* ]] && continue
            echo -e "  ${O}    ✓ ${entry}${R}"
        done < "$WHITELIST"
    else
        echo -e "  ${S}  No ports whitelisted (all incoming blocked).${R}"
    fi

    echo ""

    # Another firewall in front makes Stoa's allow rules ineffective: every
    # base chain with policy drop must accept a packet on its own.
    if command -v ufw >/dev/null 2>&1 && systemctl is-enabled ufw.service >/dev/null 2>&1; then
        echo -e "  ${T}  ufw is enabled too: a port allowed here is still dropped by ufw.${R}"
        echo -e "  ${S}  Use one of them — 'sudo ufw allow PORT' or disable ufw.${R}"
        echo ""
    fi

    # Monitor status
    if systemctl --user is-active stoa-firewall-monitor &>/dev/null; then
        echo -e "  ${O}  Port monitor: running${R}"
    else
        echo -e "  ${S}  Port monitor: stopped${R}"
    fi
    echo ""
}

cmd_ports() {
    _banner
    _init_dirs

    echo -e "  ${F}  Port   Proto  State     PID       Process${R}"
    echo -e "  ${S}  ─────  ─────  ────────  ────────  ───────────────${R}"

    # Get all listening ports with process info
    local has_ports=false
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        has_ports=true

        local proto port pid_prog state process pid
        proto=$(echo "$line" | awk '{print $1}')
        local local_addr
        local_addr=$(echo "$line" | awk '{print $5}')
        port=$(echo "$local_addr" | rev | cut -d: -f1 | rev)
        pid_prog=$(echo "$line" | awk '{print $7}')
        state=$(echo "$line" | awk '{print $2}')

        # Extract process name and PID
        if [[ "$pid_prog" =~ users:\(\(\"([^\"]+)\",pid=([0-9]+) ]]; then
            process="${BASH_REMATCH[1]}"
            pid="${BASH_REMATCH[2]}"
        else
            process="unknown"
            pid="-"
        fi

        # Check if allowed
        local status_icon
        if _is_allowed "$port" "$proto"; then
            status_icon="${O}ALLOWED${R}"
        else
            status_icon="${T}BLOCKED${R}"
        fi

        printf "  ${F}  %-5s  %-5s  ${R}%-18b  ${S}%-8s  ${F}%s${R}\n" \
            "$port" "$proto" "$status_icon" "$pid" "$process"
    done < <(ss -tlnpH 2>/dev/null | sed 's/^/tcp /'; ss -ulnpH 2>/dev/null | sed 's/^/udp /')

    if ! $has_ports; then
        echo -e "  ${S}  No listening ports found.${R}"
    fi
    echo ""
}

cmd_allow() {
    _init_dirs
    local port="$1" proto="${2:-tcp}"

    if [ -z "$port" ]; then
        echo -e "  ${T}Usage: stoa-firewall allow <port> [tcp|udp]${R}"
        return 1
    fi

    _validate_port_proto "$port" "$proto" || return 1

    if _is_allowed "$port" "$proto"; then
        echo -e "  ${S}Port ${port}/${proto} is already allowed.${R}"
        return 0
    fi

    echo "${port}/${proto}" >> "$WHITELIST"
    if ! _apply_rules; then
        sed -i "/^${port}\/${proto}$/d" "$WHITELIST"   # not applied: do not list it as allowed
        return 1
    fi
    echo -e "  ${O}[✓] Port ${port}/${proto} allowed.${R}"
    _notify "Port ${port}/${proto} allowed"
}

cmd_deny() {
    _init_dirs
    local port="$1" proto="${2:-tcp}"

    if [ -z "$port" ]; then
        echo -e "  ${T}Usage: stoa-firewall deny <port> [tcp|udp]${R}"
        return 1
    fi

    _validate_port_proto "$port" "$proto" || return 1

    if ! _is_allowed "$port" "$proto"; then
        echo -e "  ${S}Port ${port}/${proto} is already blocked.${R}"
        return 0
    fi

    sed -i "/^${port}\/${proto}$/d" "$WHITELIST"
    if ! _apply_rules; then
        echo "${port}/${proto}" >> "$WHITELIST"   # not applied: it is still open
        return 1
    fi
    echo -e "  ${O}[✓] Port ${port}/${proto} blocked.${R}"
    _notify "Port ${port}/${proto} blocked"
}

cmd_enable() {
    _init_dirs
    _apply_rules --enable-service || return 1
    echo -e "  ${O}[✓] Firewall enabled.${R}"
    _notify "Firewall enabled"
}

cmd_disable() {
    _priv sh -c 'nft delete table inet stoa_firewall 2>/dev/null; rm -f -- "$1"' \
        stoa-root "$NFT_RULES" || return 1
    echo -e "  ${T}[!] Firewall disabled. All ports open.${R}"
    _notify "Firewall disabled — all ports open"
}

# ══════════════════════════════════════════════════════════════
#   PORT MONITOR DAEMON
# ══════════════════════════════════════════════════════════════

cmd_monitor() {
    _init_dirs

    # Snapshot current ports as known
    ss -tlnpH 2>/dev/null | awk '{print $4}' | rev | cut -d: -f1 | rev | sort -n > "$KNOWN_PORTS"
    ss -ulnpH 2>/dev/null | awk '{print $4}' | rev | cut -d: -f1 | rev | sort -n >> "$KNOWN_PORTS"

    while true; do
        sleep 5

        local current_ports
        current_ports=$(mktemp)
        ss -tlnpH 2>/dev/null | awk '{print "tcp " $4 " " $6}' > "$current_ports"
        ss -ulnpH 2>/dev/null | awk '{print "udp " $4 " " $6}' >> "$current_ports"

        while IFS= read -r line; do
            [ -z "$line" ] && continue
            local proto local_addr pid_prog port process
            proto=$(echo "$line" | awk '{print $1}')
            local_addr=$(echo "$line" | awk '{print $2}')
            port=$(echo "$local_addr" | rev | cut -d: -f1 | rev)
            pid_prog=$(echo "$line" | awk '{print $3}')

            # Skip already known ports
            grep -qx "$port" "$KNOWN_PORTS" 2>/dev/null && continue

            # Skip already whitelisted
            _is_allowed "$port" "$proto" && {
                echo "$port" >> "$KNOWN_PORTS"
                continue
            }

            # Extract process name
            if [[ "$pid_prog" =~ users:\(\(\"([^\"]+)\" ]]; then
                process="${BASH_REMATCH[1]}"
            else
                process="unknown"
            fi

            # Add to known so we don't re-notify
            echo "$port" >> "$KNOWN_PORTS"

            # Send notification with action
            local action
            action=$(notify-send -t 0 -u critical \
                -A "allow=Allow" -A "deny=Deny" \
                "Stoa Firewall" \
                "New port detected: ${port}/${proto}\nProcess: ${process}\n\nAllow this port?" \
                2>/dev/null)

            case "$action" in
                allow)
                    cmd_allow "$port" "$proto"
                    ;;
                deny)
                    _notify "Port ${port}/${proto} (${process}) stays blocked"
                    ;;
            esac
        done < "$current_ports"

        rm -f "$current_ports"
    done
}

# Authorize a port (called from notification action)
cmd_authorize() {
    _init_dirs
    local port="$1" proto="${2:-tcp}"
    [ -z "$port" ] && return 1
    _validate_port_proto "$port" "$proto" || return 1

    echo "${port}/${proto}" >> "$WHITELIST"
    if ! _apply_rules; then
        sed -i "/^${port}\/${proto}$/d" "$WHITELIST"
        return 1
    fi
    _notify "Port ${port}/${proto} permanently allowed"
}

# ── Install systemd user service ──
_install_monitor_service() {
    local service_dir="${HOME}/.config/systemd/user"
    mkdir -p "$service_dir"

    cat > "${service_dir}/stoa-firewall-monitor.service" <<EOF
[Unit]
Description=Stoa Firewall Port Monitor
After=graphical-session.target

[Service]
Type=simple
ExecStart=%h/.local/bin/stoa-firewall monitor
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable --now stoa-firewall-monitor 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
#   MAIN
# ══════════════════════════════════════════════════════════════

case "${1:-status}" in
    setup)     cmd_setup ;;
    status)    cmd_status ;;
    ports)     cmd_ports ;;
    allow)     cmd_allow "$2" "$3" ;;
    deny)      cmd_deny "$2" "$3" ;;
    enable)    cmd_enable ;;
    disable)   cmd_disable ;;
    monitor)   cmd_monitor ;;
    active)    _fw_active ;;
    authorize) cmd_authorize "$2" "$3" ;;
    *)
        echo -e "  ${T}Unknown command: $1${R}"
        echo -e "  ${S}Usage: stoa-firewall {setup|status|ports|allow|deny|enable|disable|monitor}${R}"
        exit 1
        ;;
esac
