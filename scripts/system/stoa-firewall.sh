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
  allow PORT [tcp|udp] [--keep]
                          allow a port until the next reboot (default: tcp); --keep makes
                          it permanent. Permanent today: see "status"
  deny PORT [tcp|udp]     close a port (temporary or permanent)
  authorize PORT [tcp|udp]  allow a port permanently without checks; used by the monitor's
                          notification action
  enable                  enable nftables at boot
  disable                 disable it
  port PORT [tcp|udp]     everything about one port: process, user, binary, who is
                          connected, what got through/was dropped, allow/deny history
  log [HOURS]             allow/deny history and traffic summary (default 24h)
  allowed                 list every allowed port, one per line
  rules [boot]            print the ruleset (boot = what /etc keeps for the next boot)
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
# Two lists. PERMANENT survives reboots and is the only thing written to /etc
# (loaded at boot, no prompt needed). WHITELIST is the temporary one: it is
# loaded live and wiped on the first run after each boot (_boot_reset), so a
# port that was opened once for some app is closed again at the next boot.
WHITELIST="${STOA_FW_DIR}/allowed-ports.conf"
PERMANENT="${STOA_FW_DIR}/permanent-ports.conf"
BOOT_ID_FILE="${STOA_FW_DIR}/boot-id"
KNOWN_PORTS="${STOA_FW_DIR}/known-ports.list"
NFT_RULES="/etc/nftables.d/stoa-firewall.conf"
AUDIT_LOG="${STOA_FW_DIR}/audit.log"

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
        # No root without asking. A drop logged lately proves the table is
        # loaded; failing that, the persisted rules file plus an enabled
        # nftables.service (it is a oneshot: it is never "active", so that
        # says nothing) mean it is configured and loads at boot.
        journalctl -k --no-pager -o cat --since -10min --grep 'stoa-fw-(drop|pass):' 2>/dev/null | grep -q . && return 0
        [ -s "$NFT_RULES" ] && systemctl is-enabled --quiet nftables
    fi
}

_init_dirs() {
    mkdir -p "$STOA_FW_DIR"
    touch "$WHITELIST" "$KNOWN_PORTS"
    # First ever run: Enpass (browser integration) is the one port that stays.
    [ -e "$PERMANENT" ] || echo "10391/tcp" > "$PERMANENT"
    _boot_reset
}

# New boot since the last run -> forget the temporary allows. The rules
# loaded at boot came from /etc and hold only PERMANENT, so this keeps the
# list (and what the UI shows) equal to what the firewall really does.
_boot_reset() {
    local now last
    now=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null) || return 0
    last=$(cat "$BOOT_ID_FILE" 2>/dev/null)
    if [ -n "$last" ] && [ "$last" != "$now" ]; then
        if [ -s "$WHITELIST" ]; then
            local e
            while IFS= read -r e; do
                [ -n "$e" ] && printf '%s  %-9s %-11s via=boot-reset  listener=-\n' \
                    "$(date '+%F %T')" deny "$e" >> "$AUDIT_LOG" 2>/dev/null
            done < "$WHITELIST"
        fi
        : > "$WHITELIST"
    fi
    echo "$now" > "$BOOT_ID_FILE"
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

# ── Who is listening on PORT/PROTO: "name(pid)" or "-" ──
_listener_of() {
    local port="$1" proto="${2:-tcp}" flag=-tlnpH
    [ "$proto" = udp ] && flag=-ulnpH
    ss "$flag" 2>/dev/null | awk -v p="$port" '
        { n = split($4, a, ":"); if (a[n] == p) { print $NF; exit } }' |
        sed -nE 's/.*\(\("([^"]+)",pid=([0-9]+).*/\1(\2)/p' | head -1 | grep . || echo "-"
}

# ── Audit: who allowed/blocked what, and what was listening then ──
# $1 action (allow|deny|authorize)  $2 port/proto.  The source is STOA_FW_SOURCE
# (the monitor and the settings panel set it), else the calling process.
_audit() {
    local src="${STOA_FW_SOURCE:-$(ps -o comm= -p "$PPID" 2>/dev/null)}"
    printf '%s  %-9s %-11s via=%s  listener=%s\n' "$(date '+%F %T')" "$1" "$2" \
        "${src:-?}" "$(_listener_of "${2%/*}" "${2#*/}")" >> "$AUDIT_LOG" 2>/dev/null
}

# ── Check if port is in whitelist ──
_is_allowed() {
    local port="$1" proto="${2:-tcp}"
    grep -qx "${port}/${proto}" "$WHITELIST" "$PERMANENT" 2>/dev/null
}

# Every allowed entry, one per line. "boot" = only what survives a reboot.
_allowed_entries() {
    if [ "${1:-}" = boot ]; then cat "$PERMANENT" 2>/dev/null
    else cat "$PERMANENT" "$WHITELIST" 2>/dev/null; fi | sed '/^$/d;/^#/d' | awk '!seen[$0]++'
}

# ── Generate nftables rules from whitelist ──
_generate_rules() {
    # $1 = boot -> only the permanent ports (what /etc keeps for the next boot)
    local mode="${1:-}" rules="" tcp_ports="" udp_ports="" entries
    entries=$(_allowed_entries "$mode")
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
    if [ -n "$entries" ]; then
        local accepts="" port proto
        while IFS= read -r entry; do
            [ -z "$entry" ] && continue
            [[ "$entry" == \#* ]] && continue
            port=$(echo "$entry" | cut -d/ -f1)
            proto=$(echo "$entry" | cut -d/ -f2)
            accepts+="        ${proto} dport ${port} accept\n"
            case "$proto" in
                tcp) tcp_ports+="${tcp_ports:+,}${port}" ;;
                udp) udp_ports+="${udp_ports:+,}${port}" ;;
            esac
        done <<< "$entries"
        rules+="\n"
        rules+="        # What got through: new connections on allowed ports (rate-limited).\n"
        rules+="        # 'stoa-firewall port N' and 'log' read these. An accept ends the\n"
        rules+="        # chain, so the log rules have to come before the accepts.\n"
        [ -n "$tcp_ports" ] && rules+="        tcp dport { ${tcp_ports} } ct state new limit rate 30/minute log prefix \"stoa-fw-pass: \"\n"
        [ -n "$udp_ports" ] && rules+="        udp dport { ${udp_ports} } ct state new limit rate 30/minute log prefix \"stoa-fw-pass: \"\n"
        rules+="\n"
        rules+="        # Whitelisted ports\n"
        rules+="$accepts"
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
live=$1 boot=$2 dest=$3 enable=$4 inc=$5
mkdir -p "$(dirname "$dest")" || exit 2
staged="$dest.new"
# Copy into root-owned files first: what is validated is what is loaded, and
# the user-owned temp files cannot be swapped in between.
install -m 0644 -o root -g root "$boot" "$staged" || exit 2
install -m 0600 -o root -g root "$live" "$staged.live" || { rm -f "$staged"; exit 2; }
# Dry-run BEFORE flushing the old table. Without this, a syntax error leaves
# the firewall fully open.
if ! nft -c -f "$staged.live" 2>/dev/null || ! nft -c -f "$staged" 2>/dev/null; then
    rm -f "$staged" "$staged.live"; exit 3
fi
[ "$enable" = 1 ] && systemctl enable nftables --now >/dev/null 2>&1
if [ "$inc" = 1 ] && ! grep -q "include.*nftables.d" /etc/nftables.conf 2>/dev/null; then
    echo "include \"/etc/nftables.d/*.conf\"" >> /etc/nftables.conf
fi
nft delete table inet stoa_firewall 2>/dev/null
if ! nft -f "$staged.live"; then rm -f "$staged" "$staged.live"; exit 4; fi
rm -f "$staged.live"
# On disk: only the permanent ports. Temporary ones are live, gone at reboot.
mv -f "$staged" "$dest"
'

# _apply_rules [--enable-service] [--ensure-include]
_apply_rules() {
    local enable=0 inc=0 arg tmpfile bootfile rc
    for arg in "$@"; do
        case "$arg" in
            --enable-service) enable=1 ;;
            --ensure-include) inc=1 ;;
        esac
    done
    tmpfile=$(mktemp); bootfile=$(mktemp)
    _generate_rules > "$tmpfile"
    _generate_rules boot > "$bootfile"
    chmod 0644 "$tmpfile" "$bootfile"

    _priv bash -c "$_ROOT_APPLY" stoa-root "$tmpfile" "$bootfile" "$NFT_RULES" "$enable" "$inc"
    rc=$?
    rm -f "$tmpfile" "$bootfile"
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
    _init_dirs
    if [ -n "$(_allowed_entries)" ]; then
        echo -e "  ${F}  Allowed ports:${R}"
        while IFS= read -r entry; do
            if grep -qx "$entry" "$PERMANENT" 2>/dev/null; then
                echo -e "  ${O}    ✓ ${entry}${S}  permanent${R}"
            else
                echo -e "  ${O}    ✓ ${entry}${S}  until reboot${R}"
            fi
        done < <(_allowed_entries)
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

    echo -e "  ${F}  Port   Proto  State     PID       Process          Reachable from${R}"
    echo -e "  ${S}  ─────  ─────  ────────  ────────  ───────────────  ──────────────${R}"

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

        # Loopback never goes through the firewall (iif lo accept).
        local reach="network"
        case "$local_addr" in 127.*|"[::1]"*|::1*) reach="this machine only" ;; esac

        printf "  ${F}  %-5s  %-5s  ${R}%-18b  ${S}%-8s  ${F}%-15s  ${S}%s${R}\n" \
            "$port" "$proto" "$status_icon" "$pid" "$process" "$reach"
    done < <(ss -tlnpH 2>/dev/null | sed 's/^/tcp /'; ss -ulnpH 2>/dev/null | sed 's/^/udp /')

    if ! $has_ports; then
        echo -e "  ${S}  No listening ports found.${R}"
    fi
    echo ""
}

cmd_allow() {
    _init_dirs
    local port="$1" proto="${2:-tcp}" keep=0 list="$WHITELIST"
    if [ "$proto" = "--keep" ]; then proto=tcp; keep=1; fi
    if [ "${3:-}" = "--keep" ]; then keep=1; fi
    [ "$keep" = 1 ] && list="$PERMANENT"

    if [ -z "$port" ]; then
        echo -e "  ${T}Usage: stoa-firewall allow <port> [tcp|udp]${R}"
        return 1
    fi

    _validate_port_proto "$port" "$proto" || return 1

    if grep -qx "${port}/${proto}" "$PERMANENT" 2>/dev/null; then
        echo -e "  ${S}Port ${port}/${proto} is already allowed (permanent).${R}"
        return 0
    fi
    if [ "$keep" = 0 ] && _is_allowed "$port" "$proto"; then
        echo -e "  ${S}Port ${port}/${proto} is already allowed (until reboot; use --keep to make it permanent).${R}"
        return 0
    fi

    echo "${port}/${proto}" >> "$list"
    if ! _apply_rules; then
        sed -i "/^${port}\/${proto}$/d" "$list"   # not applied: do not list it as allowed
        return 1
    fi
    _audit allow "${port}/${proto}$([ "$keep" = 1 ] && echo ' permanent')"
    if [ "$keep" = 1 ]; then
        echo -e "  ${O}[✓] Port ${port}/${proto} allowed permanently.${R}"
    else
        echo -e "  ${O}[✓] Port ${port}/${proto} allowed until the next reboot.${R}"
    fi
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

    local was_perm=0
    grep -qx "${port}/${proto}" "$PERMANENT" 2>/dev/null && was_perm=1
    sed -i "/^${port}\/${proto}$/d" "$WHITELIST" "$PERMANENT"
    if ! _apply_rules; then
        # not applied: it is still open
        if [ "$was_perm" = 1 ]; then echo "${port}/${proto}" >> "$PERMANENT"
        else echo "${port}/${proto}" >> "$WHITELIST"; fi
        return 1
    fi
    _audit deny "${port}/${proto}"
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
#   WHO / WHAT / WHEN
# ══════════════════════════════════════════════════════════════

# journalctl line -> "SRC proto dport", from the kernel log prefixes.
_fw_hits() { # <pass|drop> [since]
    journalctl -k --no-pager -o cat --since "${2:--24h}" --grep "stoa-fw-$1:" 2>/dev/null |
        awk '{ s=""; p=""; d=""
               for (i=1;i<=NF;i++) { split($i,k,"=")
                   if (k[1]=="SRC") s=k[2]; else if (k[1]=="PROTO") p=tolower(k[2]); else if (k[1]=="DPT") d=k[2] }
               if (d != "") print s, p, d }'
}

# ── Who is behind a port: IPs (and names) talking to it, for the notification ──
# A listening socket has no "site" of its own. What can be told is (1) who has
# connected or tried to reach this port lately (firewall drop/pass log, live
# connections) and (2) which hosts the owning process is talking to right now
# (for a browser: the sites it has open). Names come from reverse DNS, so they
# are the server's name, not always the site's.
_host_of() { # IP -> "IP (name)" or "IP"
    local ip="$1" name
    case "$ip" in
        192.168.*|10.*|172.1[6-9].*|172.2?.*|172.3[01].*|127.*|fe80:*) echo "$ip (local network)"; return ;;
    esac
    name=$(timeout 2 getent hosts "$ip" 2>/dev/null | awk '{print $2; exit}')
    if [ -n "$name" ]; then echo "$ip ($name)"; else echo "$ip"; fi
}

# Short form for the toast: the card is small and clips what does not fit, so
# a name is cut to its last two labels ("fbcdn.net", not the whole rDNS).
_host_short() { # IP -> "LAN IP" | "name.tld" | "IP"
    local full name
    full=$(_host_of "$1")
    case "$full" in
        *"(local network)") echo "$1"; return ;;
        *" ("*")") name="${full#* (}"; name="${name%)}"
                   echo "$name" | awk -F. 'NF>2 {print $(NF-1) "." $NF; next} {print}' ;;
        *) echo "$1" ;;
    esac
}

# Compact on purpose: at most 2 lines of ~40 characters each.
_port_context() { # port proto pid -> up to 2 lines (may be empty)
    local port="$1" proto="$2" pid="$3" ip n out="" list=""
    local from
    from=$( { _fw_hits drop -3min; _fw_hits pass -3min; } 2>/dev/null |
        awk -v p="$port" -v pr="$proto" '$3==p && $2==pr {print $1}' | sort | uniq -c | sort -rn | head -2)
    if [ -n "$from" ]; then
        while read -r n ip; do list+="${list:+, }$(_host_short "$ip")"; done <<< "$from"
        out+="Tried to reach: ${list}"$'\n'
    fi
    if [ -n "$pid" ] && [ -d "/proc/$pid" ]; then
        # A browser's network work happens in child processes: take the tree.
        local tree="$pid" kids="$pid" k pat peers
        while [ -n "$kids" ]; do
            kids=$(for k in $kids; do ps -o pid= --ppid "$k" 2>/dev/null; done | xargs)
            tree+=" $kids"
        done
        pat=$(for k in $tree; do printf 'pid=%s,|' "$k"; done); pat="${pat%|}"
        peers=$(ss -tnpH state established 2>/dev/null | grep -E "$pat" |
            awk '{ sub(/:[0-9]+$/, "", $4); print $4 }' |
            sed 's/^\[//;s/\]$//' | sort | uniq -c | sort -rn | head -3)
        list=""
        if [ -n "$peers" ]; then
            while read -r n ip; do list+="${list:+, }$(_host_short "$ip")"; done <<< "$peers"
            out+="Talking to: ${list}"$'\n'
        fi
    fi
    printf '%s' "$out"
}

# stoa-firewall port PORT [tcp|udp] — everything known about one port.
cmd_port() {
    _init_dirs
    local port="$1" want="${2:-}"
    [ -z "$port" ] && { echo -e "  ${T}Usage: stoa-firewall port <port> [tcp|udp]${R}"; return 1; }
    _validate_port_proto "$port" "${want:-tcp}" || return 1
    _banner

    local proto flag found=false
    for proto in tcp udp; do
        [ -n "$want" ] && [ "$proto" != "$want" ] && continue
        flag=-tlnpH; [ "$proto" = udp ] && flag=-ulnpH

        echo -e "  ${B}── ${port}/${proto} ──${R}"
        if _is_allowed "$port" "$proto"; then
            echo -e "  ${F}Firewall:    ${O}ALLOWED${R}"
        else
            echo -e "  ${F}Firewall:    ${T}BLOCKED${R}"
        fi

        local line addr pid name
        while IFS= read -r line; do
            addr=$(echo "$line" | awk '{print $4}')
            [ "${addr##*:}" = "$port" ] || continue
            found=true
            name=""; pid=""
            if [[ "$line" =~ users:\(\(\"([^\"]+)\",pid=([0-9]+) ]]; then
                name="${BASH_REMATCH[1]}"; pid="${BASH_REMATCH[2]}"
            fi
            echo -e "  ${F}Listening:   ${R}${addr}"
            case "$addr" in
                127.*|"[::1]"*) echo -e "  ${S}             loopback: only this machine can reach it; the firewall is not involved${R}" ;;
                *)              echo -e "  ${S}             reachable from the network (if allowed above)${R}" ;;
            esac
            if [ -n "$pid" ] && [ -d "/proc/$pid" ]; then
                echo -e "  ${F}Process:     ${R}${name} (pid ${pid}), user $(ps -o user= -p "$pid" 2>/dev/null | xargs)"
                echo -e "  ${F}Started:     ${R}$(ps -o lstart= -p "$pid" 2>/dev/null | xargs)"
                echo -e "  ${F}Binary:      ${R}$(readlink "/proc/$pid/exe" 2>/dev/null || echo '?')"
                echo -e "  ${F}Command:     ${R}$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | cut -c1-200)"
                echo -e "  ${F}Opened by:   ${R}$(ps -o comm= -p "$(ps -o ppid= -p "$pid" | xargs)" 2>/dev/null) (parent of ${name})"
            else
                echo -e "  ${F}Process:     ${S}not visible (root/another user's process, or gone)${R}"
            fi
        done < <(ss "$flag" 2>/dev/null)

        if [ "$proto" = tcp ]; then
            local conns
            conns=$(ss -tnpH state established "( sport = :${port} )" 2>/dev/null | awk '{print $3 "  <-  " $4}')
            if [ -n "$conns" ]; then
                echo -e "  ${F}Connected now:${R}"; echo "$conns" | sed 's/^/             /'
            fi
        fi

        local passed dropped
        passed=$(_fw_hits pass | awk -v p="$port" -v pr="$proto" '$3==p && $2==pr {print $1}' | sort | uniq -c | sort -rn | head -5)
        dropped=$(_fw_hits drop | awk -v p="$port" -v pr="$proto" '$3==p && $2==pr {print $1}' | sort | uniq -c | sort -rn | head -5)
        echo -e "  ${F}Got through (24h, new connections):${R}"
        echo "${passed:-  none logged}" | sed 's/^/             /'
        echo -e "  ${F}Dropped (24h; the log is rate-limited, counts are a floor):${R}"
        echo "${dropped:-  none logged}" | sed 's/^/             /'

        echo -e "  ${F}Allow/deny history:${R}"
        { grep -F " ${port}/${proto} " "$AUDIT_LOG" 2>/dev/null | tail -5; } | sed 's/^/             /'
        echo ""
    done
    $found || echo -e "  ${S}Nothing is listening on ${port} right now.${R}\n"
}

# stoa-firewall log [HOURS] — recent allow/deny actions and traffic summary.
cmd_log() {
    _init_dirs
    local hours="${1:-24}"
    [[ "$hours" =~ ^[0-9]+$ ]] || hours=24
    _banner
    echo -e "  ${F}Allow/deny history (last 20):${R}"
    if [ -s "$AUDIT_LOG" ]; then tail -20 "$AUDIT_LOG" | sed 's/^/    /'
    else echo -e "  ${S}    none yet (recorded from now on)${R}"; fi
    echo ""
    local kind label
    for kind in pass drop; do
        [ "$kind" = pass ] && label="Got through" || label="Dropped"
        echo -e "  ${F}${label}, last ${hours}h  (count  from  proto/port):${R}"
        _fw_hits "$kind" "-${hours}h" | awk '{print $1 "  " $2 "/" $3}' | sort | uniq -c | sort -rn | head -15 | sed 's/^/    /'
        echo ""
    done
    echo -e "  ${S}  Logs are rate-limited (30/min through, 5/min dropped): counts are a floor.${R}"
    echo ""
}

# ══════════════════════════════════════════════════════════════
#   PORT MONITOR DAEMON
# ══════════════════════════════════════════════════════════════

cmd_monitor() {
    _init_dirs
    export STOA_FW_SOURCE=monitor

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
            local mpid=""
            if [[ "$pid_prog" =~ users:\(\(\"([^\"]+)\",pid=([0-9]+) ]]; then
                process="${BASH_REMATCH[1]}"; mpid="${BASH_REMATCH[2]}"
            else
                process="unknown"
            fi

            # Add to known so we don't re-notify
            echo "$port" >> "$KNOWN_PORTS"

            # Send notification with action
            # Give the first packets a moment to arrive, then say who is behind it.
            sleep 3
            local action ctx
            ctx=$(_port_context "$port" "$proto" "$mpid")
            action=$(notify-send -t 0 -u critical \
                -A "allow=Allow" -A "deny=Deny" \
                "Stoa Firewall" \
                "New port: ${port}/${proto}\n${process}${mpid:+ (pid ${mpid})}${ctx:+\n${ctx}}" \
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
    _audit authorize "${port}/${proto}"
    _notify "Port ${port}/${proto} allowed until reboot"
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
    allow)     cmd_allow "$2" "$3" "$4" ;;
    deny)      cmd_deny "$2" "$3" ;;
    enable)    cmd_enable ;;
    disable)   cmd_disable ;;
    monitor)   cmd_monitor ;;
    active)    _fw_active ;;
    port)      cmd_port "$2" "$3" ;;
    allowed)   _init_dirs; _allowed_entries ;;
    rules)     _init_dirs; _generate_rules "$2" ;;
    log)       cmd_log "$2" ;;
    authorize) cmd_authorize "$2" "$3" ;;
    *)
        echo -e "  ${T}Unknown command: $1${R}"
        echo -e "  ${S}Usage: stoa-firewall {setup|status|ports|port|log|allowed|rules|allow|deny|enable|disable|monitor}${R}"
        exit 1
        ;;
esac
