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
_apply_rules() {
    local tmpfile
    tmpfile=$(mktemp)
    _generate_rules > "$tmpfile"

    # Dry-run validate the new ruleset BEFORE flushing the old one.
    # Without this, a syntax error leaves the firewall fully open.
    if ! sudo nft -c -f "$tmpfile" 2>/dev/null; then
        echo -e "  ${T}[!] Generated nftables ruleset failed validation; keeping previous ruleset.${R}" >&2
        rm -f "$tmpfile"
        return 1
    fi

    # Flush old stoa rules and apply validated new ones
    sudo nft delete table inet stoa_firewall 2>/dev/null
    if ! sudo nft -f "$tmpfile"; then
        echo -e "  ${T}[!] nft -f failed unexpectedly after validation; firewall may be inactive.${R}" >&2
        rm -f "$tmpfile"
        return 1
    fi
    rm -f "$tmpfile"

    # Save persistent rules
    sudo mkdir -p /etc/nftables.d
    _generate_rules | sudo tee "$NFT_RULES" > /dev/null
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

    # Enable nftables service
    echo -e "  ${S}  Enabling nftables service...${R}"
    sudo systemctl enable nftables --now 2>/dev/null

    # Ensure main nftables.conf includes our rules
    if ! grep -q "include.*nftables.d" /etc/nftables.conf 2>/dev/null; then
        echo -e "  ${S}  Adding include directive to /etc/nftables.conf...${R}"
        sudo mkdir -p /etc/nftables.d
        echo 'include "/etc/nftables.d/*.conf"' | sudo tee -a /etc/nftables.conf > /dev/null
    fi

    # Apply deny-all rules
    echo -e "  ${S}  Applying deny-all policy...${R}"
    _apply_rules

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

    if sudo nft list table inet stoa_firewall &>/dev/null; then
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
        local_addr=$(echo "$line" | awk '{print $4}')
        port=$(echo "$local_addr" | rev | cut -d: -f1 | rev)
        pid_prog=$(echo "$line" | awk '{print $6}')
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
    done < <(ss -tlnpH 2>/dev/null; ss -ulnpH 2>/dev/null)

    if ! $has_ports; then
        echo -e "  ${S}  No listening ports found.${R}"
    fi
    echo ""
}

# Validate that $port is a numeric 1–65535 and $proto is tcp|udp. Rejects
# arbitrary strings that would otherwise be pasted into the whitelist, the
# nftables ruleset, and the later `sed` deletion pattern.
_validate_port_proto() {
    local port="$1" proto="$2"
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo -e "  ${T}Invalid port: '${port}' (expected 1-65535).${R}"
        return 1
    fi
    if [ "$proto" != "tcp" ] && [ "$proto" != "udp" ]; then
        echo -e "  ${T}Invalid protocol: '${proto}' (expected tcp or udp).${R}"
        return 1
    fi
    return 0
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
    _apply_rules
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
    _apply_rules
    echo -e "  ${O}[✓] Port ${port}/${proto} blocked.${R}"
    _notify "Port ${port}/${proto} blocked"
}

cmd_enable() {
    _init_dirs
    _apply_rules
    sudo systemctl enable nftables --now 2>/dev/null
    echo -e "  ${O}[✓] Firewall enabled.${R}"
    _notify "Firewall enabled"
}

cmd_disable() {
    sudo nft delete table inet stoa_firewall 2>/dev/null
    sudo rm -f "$NFT_RULES"
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
        ss -tlnpH 2>/dev/null | awk '{print $1 " " $4 " " $6}' > "$current_ports"
        ss -ulnpH 2>/dev/null | awk '{print $1 " " $4 " " $6}' >> "$current_ports"

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

    echo "${port}/${proto}" >> "$WHITELIST"
    _apply_rules
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
    authorize) cmd_authorize "$2" "$3" ;;
    *)
        echo -e "  ${T}Unknown command: $1${R}"
        echo -e "  ${S}Usage: stoa-firewall {setup|status|ports|allow|deny|enable|disable|monitor}${R}"
        exit 1
        ;;
esac
