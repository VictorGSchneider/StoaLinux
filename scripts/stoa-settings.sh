#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Settings                                     ║
# ║  "Order is the first law of heaven." — Marcus Aurelius       ║
# ║                                                              ║
# ║  All-in-one settings panel via rofi.                         ║
# ║  No external settings app needed.                            ║
# ╚══════════════════════════════════════════════════════════════╝

ROFI=(rofi -dmenu -config ~/.config/rofi/config.rasi)
STOA_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/stoa.conf"
WALLDIR="${HOME}/.config/stoa/wallpapers"

# ── Helpers ──

_notify() { dunstify -t 2500 "Stoa Settings" "$1" 2>/dev/null; }

_rofi_select() {
    local prompt="$1"
    shift
    printf '%s\n' "$@" | "${ROFI[@]}" -p "$prompt"
}

_rofi_input() {
    local prompt="$1"
    echo "" | "${ROFI[@]}" -p "$prompt"
}

_rofi_confirm() {
    local msg="$1"
    local choice
    choice=$(_rofi_select "$msg" "  Yes" "  No")
    [[ "$choice" == *"Yes"* ]]
}

# ══════════════════════════════════════════════════════════════
#   DISPLAY
# ══════════════════════════════════════════════════════════════

_display_brightness() {
    local current max pct
    current=$(brightnessctl get 2>/dev/null)
    max=$(brightnessctl max 2>/dev/null)
    [ -z "$max" ] || [ "$max" -eq 0 ] && { _notify "Brightness control not available"; return; }
    pct=$((current * 100 / max))

    local choice
    choice=$(_rofi_select "  Brightness (${pct}%)" \
        "  100%" "  75%" "  50%" "  25%" "  10%" \
        "  + Increase 5%" "  − Decrease 5%")
    [ -z "$choice" ] && return

    case "$choice" in
        *100%) brightnessctl set 100% -q ;;
        *75%)  brightnessctl set 75% -q ;;
        *50%)  brightnessctl set 50% -q ;;
        *25%)  brightnessctl set 25% -q ;;
        *10%)  brightnessctl set 10% -q ;;
        *Increase*) brightnessctl set +5% -q ;;
        *Decrease*) brightnessctl set 5%- -q ;;
    esac
    pct=$(($(brightnessctl get) * 100 / max))
    _notify "Brightness: ${pct}%"
}

_display_resolution() {
    if command -v hyprctl &>/dev/null && [ -n "$WAYLAND_DISPLAY" ]; then
        # Hyprland: list available modes
        local monitor
        monitor=$(hyprctl monitors -j 2>/dev/null | jq -r '.[0].name' 2>/dev/null)
        [ -z "$monitor" ] && { _notify "No monitor detected"; return; }

        local modes
        modes=$(hyprctl monitors -j 2>/dev/null | jq -r '.[0].availableModes[]' 2>/dev/null)
        [ -z "$modes" ] && { _notify "Could not read modes"; return; }

        local current
        current=$(hyprctl monitors -j 2>/dev/null | jq -r '.[0] | "\(.width)x\(.height)@\(.refreshRate)Hz"' 2>/dev/null)

        local choice
        choice=$(echo "$modes" | "${ROFI[@]}" -p "  Resolution (${current})")
        [ -z "$choice" ] && return

        local res rate
        res=$(echo "$choice" | cut -d@ -f1)
        rate=$(echo "$choice" | cut -d@ -f2 | tr -d 'Hz')
        hyprctl keyword monitor "$monitor, ${res}@${rate}, auto, 1" &>/dev/null
        _notify "Resolution: ${choice}"
    else
        # Xorg: xrandr
        local output
        output=$(xrandr 2>/dev/null | grep " connected" | head -1 | awk '{print $1}')
        [ -z "$output" ] && { _notify "No display detected"; return; }

        local modes
        modes=$(xrandr 2>/dev/null | grep -A 20 "^${output}" | grep -oP '^\s+\K\d+x\d+' | sort -u)

        local choice
        choice=$(echo "$modes" | "${ROFI[@]}" -p "  Resolution")
        [ -z "$choice" ] && return

        xrandr --output "$output" --mode "$choice"
        _notify "Resolution: ${choice}"
    fi
}

_display_scale() {
    if command -v hyprctl &>/dev/null && [ -n "$WAYLAND_DISPLAY" ]; then
        local monitor
        monitor=$(hyprctl monitors -j 2>/dev/null | jq -r '.[0].name' 2>/dev/null)
        local current
        current=$(hyprctl monitors -j 2>/dev/null | jq -r '.[0].scale' 2>/dev/null)

        local choice
        choice=$(_rofi_select "  Scale (${current}x)" \
            "1.0" "1.25" "1.5" "1.75" "2.0")
        [ -z "$choice" ] && return

        hyprctl keyword monitor "$monitor, preferred, auto, $choice" &>/dev/null
        _notify "Scale: ${choice}x"
    else
        _notify "Scaling only available on Wayland (Hyprland)"
    fi
}

_display_rotation() {
    if command -v hyprctl &>/dev/null && [ -n "$WAYLAND_DISPLAY" ]; then
        local monitor
        monitor=$(hyprctl monitors -j 2>/dev/null | jq -r '.[0].name' 2>/dev/null)
        local current
        current=$(hyprctl monitors -j 2>/dev/null | jq -r '.[0].transform' 2>/dev/null)

        local label="Normal"
        case "$current" in
            1) label="90°" ;; 2) label="180°" ;; 3) label="270°" ;;
        esac

        local choice
        choice=$(_rofi_select "  Rotation ($label)" \
            "  Normal (0°)" \
            "  90° (portrait)" \
            "  180° (inverted)" \
            "  270° (portrait inverted)" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        local transform
        case "$choice" in
            *Normal*)  transform=0 ;;
            *90*)      transform=1 ;;
            *180*)     transform=2 ;;
            *270*)     transform=3 ;;
        esac

        hyprctl keyword monitor "$monitor, preferred, auto, 1, transform, $transform" &>/dev/null
        _notify "Rotation: $(echo "$choice" | sed 's/^[[:space:]]*//' | sed 's/^[^ ]* //')"
    else
        local output
        output=$(xrandr 2>/dev/null | grep " connected" | head -1 | awk '{print $1}')
        [ -z "$output" ] && { _notify "No display detected"; return; }

        local choice
        choice=$(_rofi_select "  Rotation" \
            "  Normal" "  Left (90°)" "  Inverted (180°)" "  Right (270°)" "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *Normal*)   xrandr --output "$output" --rotate normal ;;
            *Left*)     xrandr --output "$output" --rotate left ;;
            *Inverted*) xrandr --output "$output" --rotate inverted ;;
            *Right*)    xrandr --output "$output" --rotate right ;;
        esac
        _notify "Rotation applied"
    fi
}

_display_multi_monitor() {
    if command -v hyprctl &>/dev/null && [ -n "$WAYLAND_DISPLAY" ]; then
        local monitors
        monitors=$(hyprctl monitors -j 2>/dev/null | jq -r '.[].name' 2>/dev/null)
        local count
        count=$(echo "$monitors" | wc -l)

        if [ "$count" -lt 2 ]; then
            _notify "Only one monitor detected"
            return
        fi

        local primary secondary
        primary=$(echo "$monitors" | head -1)
        secondary=$(echo "$monitors" | tail -1)

        local choice
        choice=$(_rofi_select "  Multi-Monitor ($primary + $secondary)" \
            "  Extend right" \
            "  Extend left" \
            "  Extend above" \
            "  Extend below" \
            "  Mirror (same on both)" \
            "  Primary only ($primary)" \
            "  Secondary only ($secondary)" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        local pri_res
        pri_res=$(hyprctl monitors -j 2>/dev/null | jq -r '.[0] | "\(.width)x\(.height)"' 2>/dev/null)
        local pri_w pri_h
        pri_w=$(echo "$pri_res" | cut -dx -f1)
        pri_h=$(echo "$pri_res" | cut -dx -f2)

        case "$choice" in
            *"Extend right"*)
                hyprctl keyword monitor "$primary, preferred, 0x0, 1" &>/dev/null
                hyprctl keyword monitor "$secondary, preferred, ${pri_w}x0, 1" &>/dev/null
                _notify "Extended right"
                ;;
            *"Extend left"*)
                local sec_w
                sec_w=$(hyprctl monitors -j 2>/dev/null | jq -r '.[1].width' 2>/dev/null)
                hyprctl keyword monitor "$secondary, preferred, 0x0, 1" &>/dev/null
                hyprctl keyword monitor "$primary, preferred, ${sec_w}x0, 1" &>/dev/null
                _notify "Extended left"
                ;;
            *"Extend above"*)
                local sec_h
                sec_h=$(hyprctl monitors -j 2>/dev/null | jq -r '.[1].height' 2>/dev/null)
                hyprctl keyword monitor "$secondary, preferred, 0x0, 1" &>/dev/null
                hyprctl keyword monitor "$primary, preferred, 0x${sec_h}, 1" &>/dev/null
                _notify "Extended above"
                ;;
            *"Extend below"*)
                hyprctl keyword monitor "$primary, preferred, 0x0, 1" &>/dev/null
                hyprctl keyword monitor "$secondary, preferred, 0x${pri_h}, 1" &>/dev/null
                _notify "Extended below"
                ;;
            *Mirror*)
                hyprctl keyword monitor "$secondary, preferred, auto, 1, mirror, $primary" &>/dev/null
                _notify "Mirroring: $secondary → $primary"
                ;;
            *"Primary only"*)
                hyprctl keyword monitor "$secondary, disable" &>/dev/null
                _notify "Using $primary only"
                ;;
            *"Secondary only"*)
                hyprctl keyword monitor "$primary, disable" &>/dev/null
                _notify "Using $secondary only"
                ;;
        esac
    else
        local outputs
        outputs=$(xrandr 2>/dev/null | grep " connected" | awk '{print $1}')
        local count
        count=$(echo "$outputs" | wc -l)

        if [ "$count" -lt 2 ]; then
            _notify "Only one monitor detected"
            return
        fi

        local primary secondary
        primary=$(echo "$outputs" | head -1)
        secondary=$(echo "$outputs" | tail -1)

        local choice
        choice=$(_rofi_select "  Multi-Monitor" \
            "  Extend right" \
            "  Mirror" \
            "  Primary only ($primary)" \
            "  Secondary only ($secondary)" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *"Extend right"*)
                xrandr --output "$secondary" --auto --right-of "$primary" 2>/dev/null
                _notify "Extended right"
                ;;
            *Mirror*)
                xrandr --output "$secondary" --auto --same-as "$primary" 2>/dev/null
                _notify "Mirroring"
                ;;
            *"Primary only"*)
                xrandr --output "$secondary" --off 2>/dev/null
                _notify "Using $primary only"
                ;;
            *"Secondary only"*)
                xrandr --output "$primary" --off --output "$secondary" --auto 2>/dev/null
                _notify "Using $secondary only"
                ;;
        esac
    fi
}

menu_display() {
    while true; do
        local choice
        choice=$(_rofi_select "  Display" \
            "  Brightness" \
            "  Resolution" \
            "  Scale" \
            "  Rotation" \
            "  Multi-Monitor" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *Brightness*)      _display_brightness ;;
            *Resolution*)      _display_resolution ;;
            *Scale*)           _display_scale ;;
            *Rotation*)        _display_rotation ;;
            *"Multi-Monitor"*) _display_multi_monitor ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════
#   AUDIO
# ══════════════════════════════════════════════════════════════

_audio_volume() {
    local vol
    vol=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{printf "%.0f", $2 * 100}')
    local muted
    muted=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -c "MUTED")

    local status="$vol%"
    [ "$muted" -eq 1 ] && status="Muted"

    local choice
    choice=$(_rofi_select "  Volume (${status})" \
        "  100%" "  75%" "  50%" "  25%" \
        "  + Increase 5%" "  − Decrease 5%" \
        "  Toggle mute")
    [ -z "$choice" ] && return

    case "$choice" in
        *100%) wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.0 ;;
        *75%)  wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.75 ;;
        *50%)  wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.50 ;;
        *25%)  wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.25 ;;
        *Increase*) wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ -l 1.0 ;;
        *Decrease*) wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- ;;
        *mute*) wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
    esac
    vol=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{printf "%.0f", $2 * 100}')
    muted=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -c "MUTED")
    [ "$muted" -eq 1 ] && _notify "Audio: Muted" || _notify "Volume: ${vol}%"
}

_audio_output() {
    local sinks
    sinks=$(wpctl status 2>/dev/null | sed -n '/Sinks:/,/^$/p' | grep -oP '^\s+[\*\s]*\d+\.\s+\K.*')
    [ -z "$sinks" ] && { _notify "No audio outputs found"; return; }

    local choice
    choice=$(echo "$sinks" | "${ROFI[@]}" -p "  Output device")
    [ -z "$choice" ] && return

    local sink_id
    sink_id=$(wpctl status 2>/dev/null | sed -n '/Sinks:/,/^$/p' | grep "$choice" | grep -oP '\d+' | head -1)
    [ -n "$sink_id" ] && wpctl set-default "$sink_id" && _notify "Output: $choice"
}

_audio_input() {
    local sources
    sources=$(wpctl status 2>/dev/null | sed -n '/Sources:/,/^$/p' | grep -oP '^\s+[\*\s]*\d+\.\s+\K.*')
    [ -z "$sources" ] && { _notify "No audio inputs found"; return; }

    local choice
    choice=$(echo "$sources" | "${ROFI[@]}" -p "  Input device")
    [ -z "$choice" ] && return

    local source_id
    source_id=$(wpctl status 2>/dev/null | sed -n '/Sources:/,/^$/p' | grep "$choice" | grep -oP '\d+' | head -1)
    [ -n "$source_id" ] && wpctl set-default "$source_id" && _notify "Input: $choice"
}

menu_audio() {
    while true; do
        local choice
        choice=$(_rofi_select "  Audio" \
            "  Volume" \
            "  Output device" \
            "  Input device" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *Volume*)  _audio_volume ;;
            *Output*)  _audio_output ;;
            *Input*)   _audio_input ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════
#   NETWORK (Wi-Fi)
# ══════════════════════════════════════════════════════════════

_wifi_status() {
    if command -v nmcli &>/dev/null; then
        local connected
        connected=$(nmcli -t -f NAME,TYPE con show --active 2>/dev/null | grep wifi | cut -d: -f1)
        [ -n "$connected" ] && echo "Connected: $connected" || echo "Disconnected"
    else
        echo "NetworkManager not available"
    fi
}

_wifi_connect() {
    _notify "Scanning Wi-Fi networks..."
    nmcli device wifi rescan 2>/dev/null
    sleep 1

    local networks
    networks=$(nmcli -t -f SSID,SIGNAL,SECURITY device wifi list 2>/dev/null | \
        awk -F: '$1!="" {printf "%s  (%s%% %s)\n", $1, $2, $3}' | sort -u)
    [ -z "$networks" ] && { _notify "No Wi-Fi networks found"; return; }

    local choice
    choice=$(echo "$networks" | "${ROFI[@]}" -p "  Wi-Fi")
    [ -z "$choice" ] && return

    local ssid
    ssid=$(echo "$choice" | sed 's/  (.*//')

    # Check if already known
    if nmcli -t -f NAME con show 2>/dev/null | grep -qx "$ssid"; then
        nmcli con up "$ssid" 2>/dev/null && _notify "Connected to $ssid" || _notify "Failed to connect to $ssid"
        return
    fi

    # Need password
    local pass
    pass=$(_rofi_input "  Password for $ssid")
    [ -z "$pass" ] && return

    nmcli device wifi connect "$ssid" password "$pass" 2>/dev/null \
        && _notify "Connected to $ssid" \
        || _notify "Failed to connect to $ssid"
}

_wifi_disconnect() {
    local active
    active=$(nmcli -t -f NAME,TYPE con show --active 2>/dev/null | grep wifi | cut -d: -f1)
    [ -z "$active" ] && { _notify "Not connected to Wi-Fi"; return; }

    nmcli con down "$active" 2>/dev/null
    _notify "Disconnected from $active"
}

_wifi_forget() {
    local saved
    saved=$(nmcli -t -f NAME,TYPE con show 2>/dev/null | grep wifi | cut -d: -f1)
    [ -z "$saved" ] && { _notify "No saved networks"; return; }

    local choice
    choice=$(echo "$saved" | "${ROFI[@]}" -p "  Forget network")
    [ -z "$choice" ] && return

    _rofi_confirm "Forget $choice?" && nmcli con delete "$choice" 2>/dev/null && _notify "Forgot $choice"
}

_wifi_toggle() {
    local status
    status=$(nmcli radio wifi 2>/dev/null)
    if [ "$status" = "enabled" ]; then
        nmcli radio wifi off
        _notify "Wi-Fi disabled"
    else
        nmcli radio wifi on
        _notify "Wi-Fi enabled"
    fi
}

_net_info() {
    local lines=()

    # ── Hostname ──
    lines+=("  Hostname: $(hostnamectl hostname 2>/dev/null || hostname)")

    # ── Interfaces ──
    while IFS= read -r iface; do
        [ -z "$iface" ] && continue
        local state addr addr6 mac speed type_label

        state=$(ip -br link show "$iface" 2>/dev/null | awk '{print $2}')
        addr=$(ip -4 addr show "$iface" 2>/dev/null | grep -oP 'inet \K[0-9./]+' | head -1)
        addr6=$(ip -6 addr show "$iface" scope global 2>/dev/null | grep -oP 'inet6 \K[0-9a-f:/]+' | head -1)
        mac=$(ip link show "$iface" 2>/dev/null | grep -oP 'link/ether \K[0-9a-f:]+')
        speed=$(cat "/sys/class/net/${iface}/speed" 2>/dev/null)

        # Interface type
        if [[ "$iface" == wl* ]]; then
            type_label="Wi-Fi"
        elif [[ "$iface" == en* ]] || [[ "$iface" == eth* ]]; then
            type_label="Ethernet"
        elif [[ "$iface" == lo ]]; then
            type_label="Loopback"
        elif [[ "$iface" == tun* ]] || [[ "$iface" == proton* ]] || [[ "$iface" == wg* ]]; then
            type_label="VPN"
        elif [[ "$iface" == docker* ]] || [[ "$iface" == br-* ]] || [[ "$iface" == veth* ]]; then
            type_label="Docker"
        else
            type_label="Other"
        fi

        lines+=("")
        lines+=("  [$type_label] $iface  ($state)")
        [ -n "$addr" ] && lines+=("    IPv4: $addr")
        [ -n "$addr6" ] && lines+=("    IPv6: $addr6")
        [ -n "$mac" ] && lines+=("    MAC:  $mac")
        [ -n "$speed" ] && [ "$speed" != "-1" ] && lines+=("    Speed: ${speed} Mbps")

        # Wi-Fi details
        if [[ "$iface" == wl* ]] && command -v iwctl &>/dev/null; then
            local ssid signal freq
            ssid=$(iwctl station "$iface" show 2>/dev/null | grep "Connected network" | awk '{print $NF}')
            signal=$(iwctl station "$iface" show 2>/dev/null | grep "RSSI" | awk '{print $2}')
            [ -n "$ssid" ] && lines+=("    SSID: $ssid")
            [ -n "$signal" ] && lines+=("    Signal: ${signal} dBm")
        elif [[ "$iface" == wl* ]] && command -v nmcli &>/dev/null; then
            local ssid signal freq security
            ssid=$(nmcli -t -f NAME,TYPE con show --active 2>/dev/null | grep wifi | cut -d: -f1)
            if [ -n "$ssid" ]; then
                signal=$(nmcli -t -f IN-USE,SIGNAL device wifi list 2>/dev/null | grep '^\*' | cut -d: -f2)
                freq=$(nmcli -t -f IN-USE,FREQ device wifi list 2>/dev/null | grep '^\*' | cut -d: -f2)
                security=$(nmcli -t -f IN-USE,SECURITY device wifi list 2>/dev/null | grep '^\*' | cut -d: -f2)
                lines+=("    SSID: $ssid")
                [ -n "$signal" ] && lines+=("    Signal: ${signal}%")
                [ -n "$freq" ] && lines+=("    Freq: $freq")
                [ -n "$security" ] && lines+=("    Security: $security")
            fi
        fi
    done < <(ip -br link show 2>/dev/null | awk '{print $1}' | sed 's/@.*//')

    # ── Gateway & DNS ──
    local gw
    gw=$(ip route show default 2>/dev/null | awk '/default/ {print $3; exit}')
    [ -n "$gw" ] && lines+=("") && lines+=("  Gateway: $gw")

    local dns
    dns=$(resolvectl dns 2>/dev/null | grep -oP 'link.*: \K.*' | head -3 || \
          grep -oP '^nameserver \K.*' /etc/resolv.conf 2>/dev/null | head -3)
    if [ -n "$dns" ]; then
        lines+=("  DNS: $(echo "$dns" | tr '\n' ', ' | sed 's/,$//')")
    fi

    # ── Public IP ──
    local pub_ip
    pub_ip=$(curl -s --max-time 3 ifconfig.me 2>/dev/null)
    [ -n "$pub_ip" ] && lines+=("  Public IP: $pub_ip")

    # ── Firewall ──
    if command -v nft &>/dev/null && sudo nft list table inet stoa_firewall &>/dev/null 2>&1; then
        lines+=("  Firewall: Active")
    else
        lines+=("  Firewall: Inactive")
    fi

    # ── VPN ──
    if command -v protonvpn-cli &>/dev/null; then
        local vpn_st
        vpn_st=$(protonvpn-cli s 2>/dev/null | grep "Status:" | awk '{print $2}')
        if [ "$vpn_st" = "Connected" ]; then
            local vpn_server
            vpn_server=$(protonvpn-cli s 2>/dev/null | grep "Server:" | awk '{print $2}')
            lines+=("  VPN: Connected ($vpn_server)")
        else
            lines+=("  VPN: Disconnected")
        fi
    fi

    printf '%s\n' "${lines[@]}"
}

_wifi_saved() {
    local lines=()
    local active
    active=$(nmcli -t -f NAME,TYPE con show --active 2>/dev/null | grep wifi | cut -d: -f1)

    while IFS=: read -r name uuid type device; do
        [ "$type" != "802-11-wireless" ] && continue
        local status_icon="  "
        [ "$name" = "$active" ] && status_icon="  "
        local detail
        detail=$(nmcli -t -f 802-11-wireless.ssid,802-11-wireless-security.key-mgmt con show "$uuid" 2>/dev/null)
        local security
        security=$(echo "$detail" | grep key-mgmt | cut -d: -f2)
        [ -z "$security" ] && security="open"
        lines+=("${status_icon}${name}  (${security})")
    done < <(nmcli -t -f NAME,UUID,TYPE,DEVICE con show 2>/dev/null)

    if [ ${#lines[@]} -eq 0 ]; then
        _notify "No saved Wi-Fi networks"
        return
    fi

    local choice
    choice=$(printf '%s\n' "${lines[@]}" | "${ROFI[@]}" -p "  Saved Networks")
    [ -z "$choice" ] && return

    # Extract network name
    local net_name
    net_name=$(echo "$choice" | sed 's/^  //;s/^  //;s/  (.*//')

    local action
    action=$(_rofi_select "  $net_name" \
        "  Connect" \
        "  Forget" \
        "  Back")
    [ -z "$action" ] || [[ "$action" == *"Back"* ]] && return

    case "$action" in
        *Connect*)
            nmcli con up "$net_name" 2>/dev/null \
                && _notify "Connected to $net_name" \
                || _notify "Failed to connect to $net_name"
            ;;
        *Forget*)
            _rofi_confirm "Forget $net_name?" && \
                nmcli con delete "$net_name" 2>/dev/null && \
                _notify "Forgot $net_name"
            ;;
    esac
}

menu_network() {
    while true; do
        local status
        status=$(_wifi_status)
        local wifi_state
        wifi_state=$(nmcli radio wifi 2>/dev/null)

        local choice
        choice=$(_rofi_select "  Network ($status)" \
            "  Network info" \
            "  Connect to Wi-Fi" \
            "  Saved networks" \
            "  Disconnect" \
            "  Forget network" \
            "  Toggle Wi-Fi ($wifi_state)" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *info*)       _net_info | "${ROFI[@]}" -p "  Network Info" ;;
            *Connect*)    _wifi_connect ;;
            *Saved*)      _wifi_saved ;;
            *Disconnect*) _wifi_disconnect ;;
            *Forget*)     _wifi_forget ;;
            *Toggle*)     _wifi_toggle ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════
#   BLUETOOTH
# ══════════════════════════════════════════════════════════════

_bt_status() {
    if command -v bluetoothctl &>/dev/null; then
        local powered
        powered=$(bluetoothctl show 2>/dev/null | grep "Powered:" | awk '{print $2}')
        [ "$powered" = "yes" ] && echo "On" || echo "Off"
    else
        echo "Not available"
    fi
}

_bt_scan_connect() {
    _notify "Scanning for Bluetooth devices..."
    bluetoothctl --timeout 5 scan on &>/dev/null &
    sleep 4

    local devices
    devices=$(bluetoothctl devices 2>/dev/null | awk '{$1=""; $2=""; print substr($0,3)}' | sort)
    [ -z "$devices" ] && { _notify "No devices found"; return; }

    local choice
    choice=$(echo "$devices" | "${ROFI[@]}" -p "  Bluetooth")
    [ -z "$choice" ] && return

    local mac
    mac=$(bluetoothctl devices 2>/dev/null | grep "$choice" | awk '{print $2}')
    [ -z "$mac" ] && return

    _notify "Connecting to $choice..."
    bluetoothctl pair "$mac" 2>/dev/null
    bluetoothctl trust "$mac" 2>/dev/null
    bluetoothctl connect "$mac" 2>/dev/null \
        && _notify "Connected to $choice" \
        || _notify "Failed to connect to $choice"
}

_bt_disconnect() {
    local connected
    connected=$(bluetoothctl devices Connected 2>/dev/null | awk '{$1=""; $2=""; print substr($0,3)}')
    [ -z "$connected" ] && { _notify "No connected devices"; return; }

    local choice
    choice=$(echo "$connected" | "${ROFI[@]}" -p "  Disconnect")
    [ -z "$choice" ] && return

    local mac
    mac=$(bluetoothctl devices 2>/dev/null | grep "$choice" | awk '{print $2}')
    bluetoothctl disconnect "$mac" 2>/dev/null
    _notify "Disconnected from $choice"
}

_bt_toggle() {
    local powered
    powered=$(bluetoothctl show 2>/dev/null | grep "Powered:" | awk '{print $2}')
    if [ "$powered" = "yes" ]; then
        bluetoothctl power off 2>/dev/null
        _notify "Bluetooth disabled"
    else
        bluetoothctl power on 2>/dev/null
        _notify "Bluetooth enabled"
    fi
}

_bt_saved() {
    local lines=()
    local connected_macs
    connected_macs=$(bluetoothctl devices Connected 2>/dev/null | awk '{print $2}')

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local mac name
        mac=$(echo "$line" | awk '{print $2}')
        name=$(echo "$line" | awk '{$1=""; $2=""; print substr($0,3)}')

        local status_icon="  "
        echo "$connected_macs" | grep -qx "$mac" && status_icon="  "

        local type_info
        type_info=$(bluetoothctl info "$mac" 2>/dev/null | grep "Icon:" | awk '{print $2}')
        [ -z "$type_info" ] && type_info="device"

        lines+=("${status_icon}${name}  (${type_info})")
    done < <(bluetoothctl devices Paired 2>/dev/null)

    if [ ${#lines[@]} -eq 0 ]; then
        _notify "No saved Bluetooth devices"
        return
    fi

    local choice
    choice=$(printf '%s\n' "${lines[@]}" | "${ROFI[@]}" -p "  Saved Devices")
    [ -z "$choice" ] && return

    local dev_name
    dev_name=$(echo "$choice" | sed 's/^  //;s/^  //;s/  (.*//')

    local dev_mac
    dev_mac=$(bluetoothctl devices Paired 2>/dev/null | grep "$dev_name" | awk '{print $2}')
    [ -z "$dev_mac" ] && return

    local is_connected=false
    echo "$connected_macs" | grep -qx "$dev_mac" && is_connected=true

    local action
    if $is_connected; then
        action=$(_rofi_select "  $dev_name" \
            "  Disconnect" \
            "  Forget" \
            "  Back")
    else
        action=$(_rofi_select "  $dev_name" \
            "  Connect" \
            "  Forget" \
            "  Back")
    fi
    [ -z "$action" ] || [[ "$action" == *"Back"* ]] && return

    case "$action" in
        *Connect*)
            _notify "Connecting to $dev_name..."
            bluetoothctl connect "$dev_mac" 2>/dev/null \
                && _notify "Connected to $dev_name" \
                || _notify "Failed to connect to $dev_name"
            ;;
        *Disconnect*)
            bluetoothctl disconnect "$dev_mac" 2>/dev/null
            _notify "Disconnected from $dev_name"
            ;;
        *Forget*)
            _rofi_confirm "Forget $dev_name?" && {
                bluetoothctl untrust "$dev_mac" 2>/dev/null
                bluetoothctl remove "$dev_mac" 2>/dev/null
                _notify "Forgot $dev_name"
            }
            ;;
    esac
}

menu_bluetooth() {
    if ! command -v bluetoothctl &>/dev/null; then
        _notify "Bluetooth not available (install bluez + bluez-utils)"
        return
    fi

    while true; do
        local status
        status=$(_bt_status)

        local choice
        choice=$(_rofi_select "  Bluetooth ($status)" \
            "  Scan and connect" \
            "  Saved devices" \
            "  Disconnect device" \
            "  Toggle Bluetooth ($status)" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *Scan*)       _bt_scan_connect ;;
            *Saved*)      _bt_saved ;;
            *Disconnect*) _bt_disconnect ;;
            *Toggle*)     _bt_toggle ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════
#   WALLPAPER
# ══════════════════════════════════════════════════════════════

menu_wallpaper() {
    while true; do
        # List available wallpapers
        local walls=""
        if [ -d "$WALLDIR" ]; then
            walls=$(find "$WALLDIR" -maxdepth 1 -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" -o -name "*.webp" \) -printf '%f\n' 2>/dev/null | sort)
        fi

        local items=()
        while IFS= read -r w; do
            [ -n "$w" ] && items+=("  $w")
        done <<< "$walls"
        items+=("  Generate new wallpapers (stoa-walls)")
        items+=("  Set custom wallpaper (file path)")
        items+=("  Back")

        local choice
        choice=$(_rofi_select "  Wallpaper" "${items[@]}")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *Generate*)
                _notify "Generating wallpapers..."
                stoa-walls 2>/dev/null
                _notify "Wallpapers generated!"
                ;;
            *custom*)
                local path
                path=$(_rofi_input "  Path to wallpaper")
                [ -z "$path" ] && continue
                [ ! -f "$path" ] && { _notify "File not found: $path"; continue; }
                _apply_wallpaper "$path"
                ;;
            *)
                local name
                name=$(echo "$choice" | sed 's/^  //')
                _apply_wallpaper "${WALLDIR}/${name}"
                ;;
        esac
    done
}

_apply_wallpaper() {
    local path="$1"
    if [ -n "$WAYLAND_DISPLAY" ]; then
        pkill swaybg 2>/dev/null
        swaybg -i "$path" -m fill &
        disown
    else
        feh --bg-fill "$path" 2>/dev/null
    fi
    _notify "Wallpaper: $(basename "$path")"
}

# ══════════════════════════════════════════════════════════════
#   THEME
# ══════════════════════════════════════════════════════════════

_theme_gtk() {
    local themes
    themes=$(find /usr/share/themes ~/.local/share/themes ~/.themes -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | sort -u)
    [ -z "$themes" ] && { _notify "No GTK themes found"; return; }

    local choice
    choice=$(echo "$themes" | "${ROFI[@]}" -p "  GTK Theme")
    [ -z "$choice" ] && return

    # Update GTK 3.0
    local gtk3="${HOME}/.config/gtk-3.0/settings.ini"
    if [ -f "$gtk3" ]; then
        sed -i "s/^gtk-theme-name=.*/gtk-theme-name=${choice}/" "$gtk3"
    fi

    # Update GTK 4.0
    local gtk4="${HOME}/.config/gtk-4.0/settings.ini"
    if [ -f "$gtk4" ]; then
        sed -i "s/^gtk-theme-name=.*/gtk-theme-name=${choice}/" "$gtk4"
    fi

    # Apply via gsettings if available
    command -v gsettings &>/dev/null && gsettings set org.gnome.desktop.interface gtk-theme "$choice" 2>/dev/null

    _notify "GTK Theme: $choice"
}

_theme_icons() {
    local icons
    icons=$(find /usr/share/icons ~/.local/share/icons ~/.icons -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | grep -v "default\|hicolor\|locolor" | sort -u)
    [ -z "$icons" ] && { _notify "No icon themes found"; return; }

    local choice
    choice=$(echo "$icons" | "${ROFI[@]}" -p "  Icon Theme")
    [ -z "$choice" ] && return

    local gtk3="${HOME}/.config/gtk-3.0/settings.ini"
    [ -f "$gtk3" ] && sed -i "s/^gtk-icon-theme-name=.*/gtk-icon-theme-name=${choice}/" "$gtk3"

    local gtk4="${HOME}/.config/gtk-4.0/settings.ini"
    [ -f "$gtk4" ] && sed -i "s/^gtk-icon-theme-name=.*/gtk-icon-theme-name=${choice}/" "$gtk4"

    command -v gsettings &>/dev/null && gsettings set org.gnome.desktop.interface icon-theme "$choice" 2>/dev/null

    _notify "Icons: $choice"
}

_theme_cursor() {
    local cursors
    cursors=$(find /usr/share/icons ~/.local/share/icons ~/.icons -maxdepth 2 -name "cursors" -type d 2>/dev/null | xargs -I{} dirname {} | xargs -I{} basename {} | sort -u)
    [ -z "$cursors" ] && { _notify "No cursor themes found"; return; }

    local choice
    choice=$(echo "$cursors" | "${ROFI[@]}" -p "  Cursor Theme")
    [ -z "$choice" ] && return

    local gtk3="${HOME}/.config/gtk-3.0/settings.ini"
    [ -f "$gtk3" ] && sed -i "s/^gtk-cursor-theme-name=.*/gtk-cursor-theme-name=${choice}/" "$gtk3"

    if [ -n "$WAYLAND_DISPLAY" ] && command -v hyprctl &>/dev/null; then
        hyprctl setcursor "$choice" 24 &>/dev/null
    fi

    _notify "Cursor: $choice"
}

_theme_font_size() {
    local choice
    choice=$(_rofi_select "  Font Size" \
        "9" "10" "11" "12" "13" "14" "16")
    [ -z "$choice" ] && return

    local gtk3="${HOME}/.config/gtk-3.0/settings.ini"
    # Read current font family from settings.ini
    local current_font
    current_font=$(grep "^gtk-font-name" "$gtk3" 2>/dev/null | sed 's/^gtk-font-name=\s*//' | sed 's/\s*[0-9]*$//')
    current_font="${current_font:-EB Garamond}"

    [ -f "$gtk3" ] && sed -i "s/^gtk-font-name=.*/gtk-font-name=${current_font} ${choice}/" "$gtk3"

    command -v gsettings &>/dev/null && gsettings set org.gnome.desktop.interface font-name "${current_font} $choice" 2>/dev/null

    _notify "Font size: ${choice}pt"
}

menu_theme() {
    while true; do
        local choice
        choice=$(_rofi_select "  Theme" \
            "  GTK Theme" \
            "  Icon Theme" \
            "  Cursor Theme" \
            "  Font Size" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *GTK*)    _theme_gtk ;;
            *Icon*)   _theme_icons ;;
            *Cursor*) _theme_cursor ;;
            *Font*)   _theme_font_size ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════
#   LOCK SCREEN
# ══════════════════════════════════════════════════════════════

menu_lockscreen() {
    while true; do
        local choice
        choice=$(_rofi_select "  Lock Screen" \
            "  Lock now" \
            "  Face recognition setup" \
            "  Face recognition status" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *"Lock now"*)
                if [ -n "$WAYLAND_DISPLAY" ]; then
                    hyprlock &
                else
                    i3lock-color --blur 5 --ring-color=c49a5c --inside-color=211e19cc \
                        --line-uses-inside --keyhl-color=8a9a6c --bshl-color=b36b5a \
                        --separator-color=6e6a62 --time-color=c49a5c --date-color=d4cfc4aa \
                        --verif-color=8a9a6c --wrong-color=b36b5a --clock \
                        --time-str="%H:%M" --date-str="%A, %d %B" \
                        --time-font="JetBrains Mono" --date-font="JetBrains Mono" &
                fi
                ;;
            *"setup"*)
                kitty -e sudo stoa-face setup &
                disown
                ;;
            *"status"*)
                local status_text=""
                if command -v howdy &>/dev/null; then
                    status_text="howdy: installed"
                    for svc in sudo hyprlock login; do
                        if grep -q "pam_howdy.so" "/etc/pam.d/$svc" 2>/dev/null; then
                            status_text+="\nPAM ($svc): active"
                        else
                            status_text+="\nPAM ($svc): not configured"
                        fi
                    done
                else
                    status_text="howdy: not installed\nRun: sudo stoa-face setup"
                fi
                echo -e "$status_text" | "${ROFI[@]}" -p "  Face Recognition"
                ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════
#   VPN (ProtonVPN)
# ══════════════════════════════════════════════════════════════

_vpn_status() {
    if ! command -v protonvpn-cli &>/dev/null; then
        echo "Not installed"
        return
    fi
    local st
    st=$(protonvpn-cli s 2>/dev/null | grep "Status:" | awk '{print $2}')
    if [ "$st" = "Connected" ]; then
        local server country
        server=$(protonvpn-cli s 2>/dev/null | grep "Server:" | awk '{print $2}')
        country=$(protonvpn-cli s 2>/dev/null | grep "Country:" | awk '{$1=""; print substr($0,2)}')
        echo "Connected ($server — $country)"
    else
        echo "Disconnected"
    fi
}

_vpn_connect_fastest() {
    _notify "Connecting to fastest server..."
    protonvpn-cli c -f 2>/dev/null \
        && _notify "VPN: Connected (fastest)" \
        || _notify "VPN: Connection failed"
}

_vpn_connect_country() {
    local countries
    countries=$(_rofi_select "  Country" \
        "US  United States" \
        "BR  Brazil" \
        "JP  Japan" \
        "NL  Netherlands" \
        "CH  Switzerland" \
        "DE  Germany" \
        "GB  United Kingdom" \
        "FR  France" \
        "CA  Canada" \
        "SE  Sweden" \
        "AU  Australia" \
        "SG  Singapore")
    [ -z "$countries" ] && return

    local code
    code=$(echo "$countries" | awk '{print $1}')
    _notify "Connecting to $code..."
    protonvpn-cli c --cc "$code" 2>/dev/null \
        && _notify "VPN: Connected ($code)" \
        || _notify "VPN: Connection failed"
}

_vpn_connect_p2p() {
    _notify "Connecting to P2P server..."
    protonvpn-cli c --p2p 2>/dev/null \
        && _notify "VPN: Connected (P2P)" \
        || _notify "VPN: Connection failed"
}

_vpn_connect_secure_core() {
    _notify "Connecting to Secure Core..."
    protonvpn-cli c --sc 2>/dev/null \
        && _notify "VPN: Connected (Secure Core)" \
        || _notify "VPN: Connection failed"
}

_vpn_disconnect() {
    protonvpn-cli d 2>/dev/null
    _notify "VPN: Disconnected"
}

_vpn_reconnect() {
    _notify "Reconnecting..."
    protonvpn-cli r 2>/dev/null \
        && _notify "VPN: Reconnected" \
        || _notify "VPN: Reconnect failed"
}

_vpn_killswitch() {
    local choice
    choice=$(_rofi_select "  Kill Switch" \
        "  Enable (block traffic if VPN drops)" \
        "  Disable" \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    case "$choice" in
        *Enable*)
            protonvpn-cli ks --on 2>/dev/null
            _notify "Kill Switch: enabled"
            ;;
        *Disable*)
            protonvpn-cli ks --off 2>/dev/null
            _notify "Kill Switch: disabled"
            ;;
    esac
}

menu_vpn() {
    if ! command -v protonvpn-cli &>/dev/null; then
        _notify "ProtonVPN CLI not installed. Run post-install.sh or: yay -S protonvpn-cli"
        return
    fi

    while true; do
        local status
        status=$(_vpn_status)

        local choice
        choice=$(_rofi_select "  VPN ($status)" \
            "  Quick connect (fastest)" \
            "  Connect by country" \
            "  Connect P2P" \
            "  Connect Secure Core" \
            "  Reconnect" \
            "  Disconnect" \
            "  Kill Switch" \
            "  Status details" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *fastest*)     _vpn_connect_fastest ;;
            *country*)     _vpn_connect_country ;;
            *P2P*)         _vpn_connect_p2p ;;
            *Secure*)      _vpn_connect_secure_core ;;
            *Reconnect*)   _vpn_reconnect ;;
            *Disconnect*)  _vpn_disconnect ;;
            *Kill*)        _vpn_killswitch ;;
            *Status*)
                local details
                details=$(protonvpn-cli s 2>/dev/null)
                echo "$details" | "${ROFI[@]}" -p "  VPN Status"
                ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════
#   FIREWALL & PORTS
# ══════════════════════════════════════════════════════════════

STOA_FW_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/firewall"
WHITELIST="${STOA_FW_DIR}/allowed-ports.conf"

_fw_status() {
    if sudo nft list table inet stoa_firewall &>/dev/null 2>&1; then
        echo "Active"
    else
        echo "Inactive"
    fi
}

_fw_ports_list() {
    local lines=()
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local proto local_addr pid_prog port process
        proto=$(echo "$line" | awk '{print $1}')
        local_addr=$(echo "$line" | awk '{print $4}')
        port=$(echo "$local_addr" | rev | cut -d: -f1 | rev)
        pid_prog=$(echo "$line" | awk '{print $6}')

        if [[ "$pid_prog" =~ users:\(\(\"([^\"]+)\" ]]; then
            process="${BASH_REMATCH[1]}"
        else
            process="unknown"
        fi

        local status="BLOCKED"
        grep -qx "${port}/${proto}" "$WHITELIST" 2>/dev/null && status="ALLOWED"
        lines+=("${status}  :${port}/${proto}  ${process}")
    done < <(ss -tlnpH 2>/dev/null; ss -ulnpH 2>/dev/null)

    if [ ${#lines[@]} -eq 0 ]; then
        echo "No listening ports"
    else
        printf '%s\n' "${lines[@]}"
    fi
}

_fw_toggle_port() {
    local entry="$1"
    [ -z "$entry" ] && return
    [[ "$entry" == "No listening"* ]] && return

    local port_proto
    port_proto=$(echo "$entry" | grep -oP ':\K[0-9]+/[a-z]+')
    [ -z "$port_proto" ] && return

    local port proto
    port=$(echo "$port_proto" | cut -d/ -f1)
    proto=$(echo "$port_proto" | cut -d/ -f2)

    if grep -qx "${port}/${proto}" "$WHITELIST" 2>/dev/null; then
        # Currently allowed → block it
        if _rofi_confirm "Block port ${port}/${proto}?"; then
            stoa-firewall deny "$port" "$proto" 2>/dev/null
            _notify "Port ${port}/${proto} blocked"
        fi
    else
        # Currently blocked → allow it
        if _rofi_confirm "Allow port ${port}/${proto}?"; then
            stoa-firewall allow "$port" "$proto" 2>/dev/null
            _notify "Port ${port}/${proto} allowed"
        fi
    fi
}

menu_firewall() {
    if ! command -v nft &>/dev/null; then
        _notify "nftables not installed. Run: stoa-firewall setup"
        return
    fi

    while true; do
        local status
        status=$(_fw_status)

        local choice
        choice=$(_rofi_select "  Firewall ($status)" \
            "  View ports" \
            "  Allow a port" \
            "  Block a port" \
            "  Enable firewall" \
            "  Disable firewall" \
            "  Setup (first time)" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *"View ports"*)
                local port_choice
                port_choice=$(_fw_ports_list | "${ROFI[@]}" -p "  Ports (tap to toggle)")
                [ -n "$port_choice" ] && _fw_toggle_port "$port_choice"
                ;;
            *"Allow a port"*)
                local port_input
                port_input=$(_rofi_input "  Port to allow (e.g. 8080)")
                [ -z "$port_input" ] && continue
                local proto_choice
                proto_choice=$(_rofi_select "  Protocol" "tcp" "udp")
                [ -z "$proto_choice" ] && continue
                stoa-firewall allow "$port_input" "$proto_choice" 2>/dev/null
                _notify "Port ${port_input}/${proto_choice} allowed"
                ;;
            *"Block a port"*)
                if [ ! -s "$WHITELIST" ]; then
                    _notify "No ports in whitelist"
                    continue
                fi
                local block_choice
                block_choice=$(cat "$WHITELIST" | "${ROFI[@]}" -p "  Remove from whitelist")
                [ -z "$block_choice" ] && continue
                local bport bproto
                bport=$(echo "$block_choice" | cut -d/ -f1)
                bproto=$(echo "$block_choice" | cut -d/ -f2)
                stoa-firewall deny "$bport" "$bproto" 2>/dev/null
                _notify "Port ${bport}/${bproto} blocked"
                ;;
            *"Enable"*)
                kitty -e sudo stoa-firewall enable &
                disown
                ;;
            *"Disable"*)
                _rofi_confirm "Disable firewall? All ports will be open." && {
                    kitty -e sudo stoa-firewall disable &
                    disown
                }
                ;;
            *"Setup"*)
                kitty -e sudo stoa-firewall setup &
                disown
                ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════
#   HARDWARE & DEVICES
# ══════════════════════════════════════════════════════════════

_hw_cpu() {
    local lines=()
    local model count cores threads freq governor temp

    model=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)
    count=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null)
    cores=$(grep "cpu cores" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | xargs)
    threads="$count"
    freq=$(grep "cpu MHz" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | xargs | cut -d. -f1)
    governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)
    temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
    [ -n "$temp" ] && temp="$((temp / 1000))°C"

    lines+=("  CPU")
    [ -n "$model" ] && lines+=("    Model: $model")
    [ -n "$cores" ] && lines+=("    Cores: $cores  Threads: $threads")
    [ -n "$freq" ] && lines+=("    Freq: ${freq} MHz")
    [ -n "$governor" ] && lines+=("    Governor: $governor")
    [ -n "$temp" ] && lines+=("    Temp: $temp")

    printf '%s\n' "${lines[@]}"
}

_hw_gpu() {
    local lines=()
    lines+=("  GPU")

    if command -v lspci &>/dev/null; then
        while IFS= read -r gpu; do
            [ -z "$gpu" ] && continue
            lines+=("    $gpu")
        done < <(lspci 2>/dev/null | grep -iE 'VGA|3D|Display' | cut -d: -f3- | xargs)
    fi

    # VRAM and driver via DRM
    for card in /sys/class/drm/card[0-9]; do
        [ -d "$card" ] || continue
        local name driver vram
        name=$(basename "$card")
        driver=$(basename "$(readlink "$card/device/driver" 2>/dev/null)")
        vram=$(cat "$card/device/mem_info_vram_total" 2>/dev/null)
        [ -n "$driver" ] && lines+=("    $name driver: $driver")
        [ -n "$vram" ] && lines+=("    $name VRAM: $((vram / 1024 / 1024)) MB")
    done

    [ ${#lines[@]} -eq 1 ] && lines+=("    No GPU detected")
    printf '%s\n' "${lines[@]}"
}

_hw_memory() {
    local lines=()
    lines+=("  Memory")

    local total used avail
    total=$(free -h 2>/dev/null | awk '/^Mem:/ {print $2}')
    used=$(free -h 2>/dev/null | awk '/^Mem:/ {print $3}')
    avail=$(free -h 2>/dev/null | awk '/^Mem:/ {print $7}')
    lines+=("    Total: $total  Used: $used  Available: $avail")

    # Swap
    local swap_total swap_used
    swap_total=$(free -h 2>/dev/null | awk '/^Swap:/ {print $2}')
    swap_used=$(free -h 2>/dev/null | awk '/^Swap:/ {print $3}')
    [ -n "$swap_total" ] && [ "$swap_total" != "0B" ] && lines+=("    Swap: $swap_used / $swap_total")

    # DIMM slots
    if command -v dmidecode &>/dev/null; then
        while IFS= read -r dimm; do
            [ -z "$dimm" ] && continue
            lines+=("    $dimm")
        done < <(sudo dmidecode -t memory 2>/dev/null | awk '
            /^Memory Device$/ {dev=1; size=""; type=""; speed=""; loc=""}
            dev && /Size:/ {size=$2 " " $3}
            dev && /Type:/ && !/Type Detail/ {type=$2}
            dev && /Speed:/ && !/Configured/ {speed=$2 " " $3}
            dev && /Locator:/ && !/Bank/ {loc=$2}
            dev && /^$/ {
                if (size != "" && size !~ /No Module/) printf "%s: %s %s %s\n", loc, size, type, speed
                dev=0
            }')
    fi

    printf '%s\n' "${lines[@]}"
}

_hw_disks() {
    local lines=()
    lines+=("  Disks")

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local name size type model mountpoint pct
        name=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $2}')
        type=$(echo "$line" | awk '{print $3}')
        model=$(echo "$line" | awk '{$1=$2=$3=""; print $0}' | xargs)

        # Only show real disks and partitions
        [[ "$type" == "loop" ]] && continue
        [[ "$type" == "rom" ]] && continue

        if [[ "$name" == sd* ]] || [[ "$name" == nvme* ]] || [[ "$name" == vd* ]]; then
            [ -n "$model" ] && lines+=("    /dev/$name  $size  $model") || lines+=("    /dev/$name  $size  $type")
        fi
    done < <(lsblk -dno NAME,SIZE,TYPE,MODEL 2>/dev/null)

    # Partitions with usage
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local fs size used avail pct mount
        fs=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $2}')
        used=$(echo "$line" | awk '{print $3}')
        avail=$(echo "$line" | awk '{print $4}')
        pct=$(echo "$line" | awk '{print $5}')
        mount=$(echo "$line" | awk '{print $6}')

        [[ "$fs" == tmpfs ]] && continue
        [[ "$fs" == devtmpfs ]] && continue
        [[ "$fs" == efivarfs ]] && continue

        lines+=("      $mount  $used/$size ($pct)")
    done < <(df -h 2>/dev/null | tail -n +2)

    printf '%s\n' "${lines[@]}"
}

_hw_battery() {
    local lines=()
    local found=false

    for bat in /sys/class/power_supply/BAT*; do
        [ -d "$bat" ] || continue
        found=true
        local name status capacity health energy_full energy_full_design cycles
        name=$(basename "$bat")
        status=$(cat "$bat/status" 2>/dev/null)
        capacity=$(cat "$bat/capacity" 2>/dev/null)
        energy_full=$(cat "$bat/energy_full" 2>/dev/null || cat "$bat/charge_full" 2>/dev/null)
        energy_full_design=$(cat "$bat/energy_full_design" 2>/dev/null || cat "$bat/charge_full_design" 2>/dev/null)
        cycles=$(cat "$bat/cycle_count" 2>/dev/null)

        lines+=("  Battery ($name)")
        lines+=("    Status: $status  Charge: ${capacity}%")

        if [ -n "$energy_full" ] && [ -n "$energy_full_design" ] && [ "$energy_full_design" -gt 0 ]; then
            health=$((energy_full * 100 / energy_full_design))
            lines+=("    Health: ${health}%")
        fi

        [ -n "$cycles" ] && [ "$cycles" != "0" ] && lines+=("    Cycles: $cycles")
    done

    # AC adapter
    for ac in /sys/class/power_supply/AC* /sys/class/power_supply/ADP*; do
        [ -d "$ac" ] || continue
        local online
        online=$(cat "$ac/online" 2>/dev/null)
        [ "$online" = "1" ] && lines+=("    AC: plugged in") || lines+=("    AC: unplugged")
    done

    if ! $found; then
        lines+=("  Battery")
        lines+=("    No battery detected (desktop)")
    fi

    printf '%s\n' "${lines[@]}"
}

_hw_usb() {
    local lines=()
    lines+=("  USB Devices")

    if command -v lsusb &>/dev/null; then
        while IFS= read -r dev; do
            [ -z "$dev" ] && continue
            # Remove "Bus XXX Device XXX: ID XXXX:XXXX" prefix, keep description
            local desc
            desc=$(echo "$dev" | sed 's/^Bus [0-9]* Device [0-9]*: ID [0-9a-f]*:[0-9a-f]* //')
            [ -n "$desc" ] && lines+=("    $desc")
        done < <(lsusb 2>/dev/null)
    else
        lines+=("    lsusb not available")
    fi

    printf '%s\n' "${lines[@]}"
}

_hw_network() {
    local lines=()
    lines+=("  Network Adapters")

    if command -v lspci &>/dev/null; then
        while IFS= read -r nic; do
            [ -z "$nic" ] && continue
            lines+=("    PCI: $nic")
        done < <(lspci 2>/dev/null | grep -iE 'Network|Ethernet|Wi-Fi|Wireless' | cut -d: -f3- | xargs)
    fi

    # USB network adapters
    if command -v lsusb &>/dev/null; then
        while IFS= read -r nic; do
            [ -z "$nic" ] && continue
            local desc
            desc=$(echo "$nic" | sed 's/^Bus [0-9]* Device [0-9]*: ID [0-9a-f]*:[0-9a-f]* //')
            lines+=("    USB: $desc")
        done < <(lsusb 2>/dev/null | grep -iE 'Network|Ethernet|Wi-Fi|Wireless|802\.11')
    fi

    [ ${#lines[@]} -eq 1 ] && lines+=("    No adapters detected")
    printf '%s\n' "${lines[@]}"
}

_hw_audio() {
    local lines=()
    lines+=("  Audio Devices")

    if command -v lspci &>/dev/null; then
        while IFS= read -r dev; do
            [ -z "$dev" ] && continue
            lines+=("    $dev")
        done < <(lspci 2>/dev/null | grep -i 'Audio' | cut -d: -f3- | xargs)
    fi

    # ALSA cards
    if [ -f /proc/asound/cards ]; then
        while IFS= read -r card; do
            [ -z "$card" ] && continue
            [[ "$card" == *"["* ]] && lines+=("    ALSA: $(echo "$card" | sed 's/^[[:space:]]*[0-9]* \[/[/')")
        done < /proc/asound/cards
    fi

    [ ${#lines[@]} -eq 1 ] && lines+=("    No audio devices detected")
    printf '%s\n' "${lines[@]}"
}

_hw_sensors() {
    local lines=()
    lines+=("  Sensors")

    if command -v sensors &>/dev/null; then
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            # Show adapter headers and temperature lines
            if [[ "$line" != *"="* ]] && [[ "$line" != *"Adapter"* ]]; then
                [[ "$line" == *"°C"* ]] || [[ "$line" == *"RPM"* ]] || [[ "$line" == *"V"* ]] && \
                    lines+=("    $line")
            elif [[ "$line" == *"Adapter"* ]]; then
                lines+=("    ---")
            fi
        done < <(sensors 2>/dev/null)
    else
        # Fallback to sysfs thermal zones
        for tz in /sys/class/thermal/thermal_zone*; do
            [ -d "$tz" ] || continue
            local type temp
            type=$(cat "$tz/type" 2>/dev/null)
            temp=$(cat "$tz/temp" 2>/dev/null)
            [ -n "$temp" ] && lines+=("    $type: $((temp / 1000))°C")
        done
    fi

    # Fan speeds from sysfs
    for hwmon in /sys/class/hwmon/hwmon*; do
        [ -d "$hwmon" ] || continue
        for fan in "$hwmon"/fan*_input; do
            [ -f "$fan" ] || continue
            local rpm label
            rpm=$(cat "$fan" 2>/dev/null)
            label=$(cat "${fan%_input}_label" 2>/dev/null || basename "$fan" | sed 's/_input//')
            [ -n "$rpm" ] && [ "$rpm" != "0" ] && lines+=("    $label: ${rpm} RPM")
        done
    done

    [ ${#lines[@]} -eq 1 ] && lines+=("    No sensors detected")
    printf '%s\n' "${lines[@]}"
}

_hw_camera() {
    local lines=()
    lines+=("  Cameras")

    # Video4Linux devices
    if [ -d /sys/class/video4linux ]; then
        for dev in /sys/class/video4linux/video*; do
            [ -d "$dev" ] || continue
            local name devnode
            name=$(cat "$dev/name" 2>/dev/null)
            devnode="/dev/$(basename "$dev")"
            [ -n "$name" ] && lines+=("    $devnode: $name")
        done
    fi

    # USB cameras
    if command -v lsusb &>/dev/null; then
        while IFS= read -r cam; do
            [ -z "$cam" ] && continue
            local desc
            desc=$(echo "$cam" | sed 's/^Bus [0-9]* Device [0-9]*: ID [0-9a-f]*:[0-9a-f]* //')
            lines+=("    USB: $desc")
        done < <(lsusb 2>/dev/null | grep -iE 'Camera|Webcam|Video|Imaging')
    fi

    [ ${#lines[@]} -eq 1 ] && lines+=("    No cameras detected")
    printf '%s\n' "${lines[@]}"
}

_hw_input() {
    local lines=()
    lines+=("  Input Devices")

    # Keyboards
    local kb_found=false
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local name
        name=$(echo "$line" | grep -oP 'Name="\K[^"]+')
        [ -z "$name" ] && continue

        # Filter to real keyboards (exclude power buttons, video bus, etc.)
        local handlers
        handlers=$(grep -A4 "Name=\"$name\"" /proc/bus/input/devices 2>/dev/null | grep "Handlers=")
        [[ "$handlers" != *"kbd"* ]] && continue
        # Skip virtual/system devices
        [[ "$name" == *"Video Bus"* ]] && continue
        [[ "$name" == *"Power Button"* ]] && continue
        [[ "$name" == *"Lid Switch"* ]] && continue
        [[ "$name" == *"Sleep Button"* ]] && continue
        [[ "$name" == *"PC Speaker"* ]] && continue

        if ! $kb_found; then
            lines+=("")
            lines+=("    Keyboards")
            kb_found=true
        fi
        lines+=("      $name")
    done < <(grep "^N:" /proc/bus/input/devices 2>/dev/null)

    # Touchpads and mice
    local tp_found=false
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local name
        name=$(echo "$line" | grep -oP 'Name="\K[^"]+')
        [ -z "$name" ] && continue

        local handlers
        handlers=$(grep -A4 "Name=\"$name\"" /proc/bus/input/devices 2>/dev/null | grep "Handlers=")
        [[ "$handlers" != *"mouse"* ]] && continue

        if ! $tp_found; then
            lines+=("")
            lines+=("    Touchpads / Mice")
            tp_found=true
        fi

        local type_label="Mouse"
        [[ "$name" == *"ouchpad"* ]] || [[ "$name" == *"Touchpad"* ]] || [[ "$name" == *"TrackPad"* ]] || [[ "$name" == *"Synaptics"* ]] || [[ "$name" == *"ELAN"* ]] && type_label="Touchpad"
        [[ "$name" == *"TrackPoint"* ]] || [[ "$name" == *"pointing stick"* ]] && type_label="TrackPoint"

        lines+=("      [$type_label] $name")
    done < <(grep "^N:" /proc/bus/input/devices 2>/dev/null)

    # Touchpad settings (libinput)
    if command -v hyprctl &>/dev/null && [ -n "$WAYLAND_DISPLAY" ]; then
        local tap nat_scroll speed
        tap=$(hyprctl getoption input:touchpad:tap 2>/dev/null | grep "int:" | awk '{print $2}')
        nat_scroll=$(hyprctl getoption input:touchpad:natural_scroll 2>/dev/null | grep "int:" | awk '{print $2}')
        speed=$(hyprctl getoption input:sensitivity 2>/dev/null | grep "float:" | awk '{print $2}')
        if [ -n "$tap" ]; then
            lines+=("")
            lines+=("    Touchpad Settings")
            [ "$tap" = "1" ] && lines+=("      Tap to click: on") || lines+=("      Tap to click: off")
            [ "$nat_scroll" = "1" ] && lines+=("      Natural scroll: on") || lines+=("      Natural scroll: off")
            [ -n "$speed" ] && lines+=("      Sensitivity: $speed")
        fi
    fi

    # Keyboard layout
    local layout
    if command -v hyprctl &>/dev/null && [ -n "$WAYLAND_DISPLAY" ]; then
        layout=$(hyprctl getoption input:kb_layout 2>/dev/null | grep "str:" | awk '{print $2}')
    else
        layout=$(setxkbmap -query 2>/dev/null | grep "layout:" | awk '{print $2}')
    fi
    if [ -n "$layout" ]; then
        lines+=("")
        lines+=("    Keyboard Layout: $layout")
    fi

    [ ${#lines[@]} -eq 1 ] && lines+=("    No input devices detected")
    printf '%s\n' "${lines[@]}"
}

menu_hardware() {
    while true; do
        local choice
        choice=$(_rofi_select "  Hardware" \
            "  All devices" \
            "  CPU" \
            "  GPU" \
            "  Memory" \
            "  Disks" \
            "  Battery" \
            "  USB devices" \
            "  Network adapters" \
            "  Audio devices" \
            "  Camera" \
            "  Input (keyboard/touchpad)" \
            "  Sensors" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *"All devices"*)
                {
                    _hw_cpu; echo ""
                    _hw_gpu; echo ""
                    _hw_memory; echo ""
                    _hw_disks; echo ""
                    _hw_battery; echo ""
                    _hw_network; echo ""
                    _hw_audio; echo ""
                    _hw_camera; echo ""
                    _hw_input; echo ""
                    _hw_usb; echo ""
                    _hw_sensors
                } | "${ROFI[@]}" -p "  Hardware"
                ;;
            *CPU*)              _hw_cpu | "${ROFI[@]}" -p "  CPU" ;;
            *GPU*)              _hw_gpu | "${ROFI[@]}" -p "  GPU" ;;
            *Memory*)           _hw_memory | "${ROFI[@]}" -p "  Memory" ;;
            *Disks*)            _hw_disks | "${ROFI[@]}" -p "  Disks" ;;
            *Battery*)          _hw_battery | "${ROFI[@]}" -p "  Battery" ;;
            *USB*)              _hw_usb | "${ROFI[@]}" -p "  USB" ;;
            *"Network adapt"*)  _hw_network | "${ROFI[@]}" -p "  Network Adapters" ;;
            *Audio*)            _hw_audio | "${ROFI[@]}" -p "  Audio" ;;
            *Camera*)           _hw_camera | "${ROFI[@]}" -p "  Camera" ;;
            *Input*)            _hw_input | "${ROFI[@]}" -p "  Input Devices" ;;
            *Sensors*)          _hw_sensors | "${ROFI[@]}" -p "  Sensors" ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════
#   MOUSE & TOUCHPAD
# ══════════════════════════════════════════════════════════════

STOA_INPUT_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/input.conf"

_input_save() {
    local key="$1" val="$2"
    mkdir -p "$(dirname "$STOA_INPUT_CONF")"
    touch "$STOA_INPUT_CONF"
    if grep -q "^${key}=" "$STOA_INPUT_CONF" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$STOA_INPUT_CONF"
    else
        echo "${key}=${val}" >> "$STOA_INPUT_CONF"
    fi
}

_input_get() {
    local key="$1" default="$2"
    local val
    val=$(grep "^${key}=" "$STOA_INPUT_CONF" 2>/dev/null | cut -d= -f2)
    echo "${val:-$default}"
}

# ── Apply to Hyprland (live) ──
_input_apply_hypr() {
    local key="$1" val="$2"
    hyprctl keyword "$key" "$val" &>/dev/null
}

# ── Apply to Xorg via xinput ──
_xinput_set() {
    local prop="$1" val="$2"
    while IFS= read -r id; do
        [ -z "$id" ] && continue
        xinput set-prop "$id" "$prop" $val 2>/dev/null
    done < <(xinput list --id-only 2>/dev/null)
}

# ── Sensitivity / Speed ──
_mouse_sensitivity() {
    local current
    if [ -n "$WAYLAND_DISPLAY" ]; then
        current=$(hyprctl getoption input:sensitivity 2>/dev/null | grep "float:" | awk '{print $2}')
    else
        current=$(_input_get "sensitivity" "0")
    fi

    local choice
    choice=$(_rofi_select "  Sensitivity ($current)" \
        "-1.0  (very slow)" \
        "-0.75" \
        "-0.5  (slow)" \
        "-0.25" \
        " 0.0  (default)" \
        " 0.25" \
        " 0.5  (fast)" \
        " 0.75" \
        " 1.0  (very fast)")
    [ -z "$choice" ] && return

    local val
    val=$(echo "$choice" | awk '{print $1}')

    if [ -n "$WAYLAND_DISPLAY" ]; then
        _input_apply_hypr "input:sensitivity" "$val"
    else
        # xinput: map -1..1 to 0.25..4.0 (accel speed)
        _xinput_set "libinput Accel Speed" "$val"
    fi
    _input_save "sensitivity" "$val"
    _notify "Sensitivity: $val"
}

# ── Acceleration Profile ──
_mouse_accel_profile() {
    local current
    if [ -n "$WAYLAND_DISPLAY" ]; then
        current=$(hyprctl getoption input:accel_profile 2>/dev/null | grep "str:" | awk '{print $2}')
        [ -z "$current" ] && current="(default)"
    else
        current=$(_input_get "accel_profile" "adaptive")
    fi

    local choice
    choice=$(_rofi_select "  Accel Profile ($current)" \
        "adaptive  (accelerates with speed)" \
        "flat  (constant speed, no accel)" \
        "custom")
    [ -z "$choice" ] && return

    local val
    val=$(echo "$choice" | awk '{print $1}')

    if [ -n "$WAYLAND_DISPLAY" ]; then
        _input_apply_hypr "input:accel_profile" "$val"
    else
        case "$val" in
            adaptive) _xinput_set "libinput Accel Profile Enabled" "1 0" ;;
            flat)     _xinput_set "libinput Accel Profile Enabled" "0 1" ;;
        esac
    fi
    _input_save "accel_profile" "$val"
    _notify "Accel profile: $val"
}

# ── Scroll Direction ──
_mouse_natural_scroll() {
    local current label
    if [ -n "$WAYLAND_DISPLAY" ]; then
        current=$(hyprctl getoption input:natural_scroll 2>/dev/null | grep "int:" | awk '{print $2}')
    else
        current=$(_input_get "natural_scroll" "0")
    fi
    [ "$current" = "1" ] || [ "$current" = "true" ] && label="on" || label="off"

    local choice
    choice=$(_rofi_select "  Natural Scroll ($label)" \
        "  Enable (scroll follows content)" \
        "  Disable (traditional)")
    [ -z "$choice" ] && return

    local val
    [[ "$choice" == *"Enable"* ]] && val=1 || val=0

    if [ -n "$WAYLAND_DISPLAY" ]; then
        _input_apply_hypr "input:natural_scroll" "$val"
    else
        _xinput_set "libinput Natural Scrolling Enabled" "$val"
    fi
    _input_save "natural_scroll" "$val"
    [ "$val" = "1" ] && _notify "Natural scroll: on" || _notify "Natural scroll: off"
}

# ── Scroll Speed (Hyprland) ──
_mouse_scroll_factor() {
    local current
    current=$(hyprctl getoption input:scroll_factor 2>/dev/null | grep "float:" | awk '{print $2}')
    [ -z "$current" ] && current="1.0"

    local choice
    choice=$(_rofi_select "  Scroll Speed ($current)" \
        "0.5  (slow)" \
        "0.75" \
        "1.0  (default)" \
        "1.5" \
        "2.0  (fast)" \
        "3.0  (very fast)")
    [ -z "$choice" ] && return

    local val
    val=$(echo "$choice" | awk '{print $1}')

    if [ -n "$WAYLAND_DISPLAY" ]; then
        _input_apply_hypr "input:scroll_factor" "$val"
    fi
    _input_save "scroll_factor" "$val"
    _notify "Scroll speed: $val"
}

# ── Left-handed Mode ──
_mouse_left_handed() {
    local current label
    if [ -n "$WAYLAND_DISPLAY" ]; then
        current=$(hyprctl getoption input:left_handed 2>/dev/null | grep "int:" | awk '{print $2}')
    else
        current=$(_input_get "left_handed" "0")
    fi
    [ "$current" = "1" ] && label="on" || label="off"

    local choice
    choice=$(_rofi_select "  Left-handed ($label)" \
        "  Enable (swap left/right buttons)" \
        "  Disable (right-handed)")
    [ -z "$choice" ] && return

    local val
    [[ "$choice" == *"Enable"* ]] && val=1 || val=0

    if [ -n "$WAYLAND_DISPLAY" ]; then
        _input_apply_hypr "input:left_handed" "$val"
    else
        _xinput_set "libinput Left Handed Enabled" "$val"
    fi
    _input_save "left_handed" "$val"
    [ "$val" = "1" ] && _notify "Left-handed: on" || _notify "Left-handed: off"
}

# ── Follow Mouse (Hyprland focus policy) ──
_mouse_follow() {
    local current
    current=$(hyprctl getoption input:follow_mouse 2>/dev/null | grep "int:" | awk '{print $2}')
    [ -z "$current" ] && current="1"

    local choice
    choice=$(_rofi_select "  Focus follows mouse ($current)" \
        "0  (click to focus)" \
        "1  (focus on hover, click to raise)" \
        "2  (focus on hover, no raise)" \
        "3  (focus on hover, always raise)")
    [ -z "$choice" ] && return

    local val
    val=$(echo "$choice" | awk '{print $1}')

    _input_apply_hypr "input:follow_mouse" "$val"
    _input_save "follow_mouse" "$val"
    _notify "Follow mouse: $val"
}

# ── Touchpad: Tap to Click ──
_tp_tap() {
    local current label
    if [ -n "$WAYLAND_DISPLAY" ]; then
        current=$(hyprctl getoption input:touchpad:tap-to-click 2>/dev/null | grep "int:" | awk '{print $2}')
    else
        current=$(_input_get "tap_to_click" "1")
    fi
    [ "$current" = "1" ] && label="on" || label="off"

    local choice
    choice=$(_rofi_select "  Tap to Click ($label)" \
        "  Enable" \
        "  Disable")
    [ -z "$choice" ] && return

    local val
    [[ "$choice" == *"Enable"* ]] && val=1 || val=0

    if [ -n "$WAYLAND_DISPLAY" ]; then
        _input_apply_hypr "input:touchpad:tap-to-click" "$val"
    else
        _xinput_set "libinput Tapping Enabled" "$val"
    fi
    _input_save "tap_to_click" "$val"
    [ "$val" = "1" ] && _notify "Tap to click: on" || _notify "Tap to click: off"
}

# ── Touchpad: Natural Scroll ──
_tp_natural_scroll() {
    local current label
    if [ -n "$WAYLAND_DISPLAY" ]; then
        current=$(hyprctl getoption input:touchpad:natural_scroll 2>/dev/null | grep "int:" | awk '{print $2}')
    else
        current=$(_input_get "tp_natural_scroll" "1")
    fi
    [ "$current" = "1" ] || [ "$current" = "true" ] && label="on" || label="off"

    local choice
    choice=$(_rofi_select "  TP Natural Scroll ($label)" \
        "  Enable (scroll follows content)" \
        "  Disable (traditional)")
    [ -z "$choice" ] && return

    local val
    [[ "$choice" == *"Enable"* ]] && val=1 || val=0

    if [ -n "$WAYLAND_DISPLAY" ]; then
        _input_apply_hypr "input:touchpad:natural_scroll" "$val"
    else
        _xinput_set "libinput Natural Scrolling Enabled" "$val"
    fi
    _input_save "tp_natural_scroll" "$val"
    [ "$val" = "1" ] && _notify "TP natural scroll: on" || _notify "TP natural scroll: off"
}

# ── Touchpad: Disable While Typing ──
_tp_dwt() {
    local current label
    if [ -n "$WAYLAND_DISPLAY" ]; then
        current=$(hyprctl getoption input:touchpad:disable_while_typing 2>/dev/null | grep "int:" | awk '{print $2}')
    else
        current=$(_input_get "dwt" "1")
    fi
    [ "$current" = "1" ] && label="on" || label="off"

    local choice
    choice=$(_rofi_select "  Disable while typing ($label)" \
        "  Enable (prevents accidental touches)" \
        "  Disable")
    [ -z "$choice" ] && return

    local val
    [[ "$choice" == *"Enable"* ]] && val=1 || val=0

    if [ -n "$WAYLAND_DISPLAY" ]; then
        _input_apply_hypr "input:touchpad:disable_while_typing" "$val"
    else
        _xinput_set "libinput Disable While Typing Enabled" "$val"
    fi
    _input_save "dwt" "$val"
    [ "$val" = "1" ] && _notify "Disable while typing: on" || _notify "Disable while typing: off"
}

# ── Touchpad: Scroll Method ──
_tp_scroll_method() {
    local current
    if [ -n "$WAYLAND_DISPLAY" ]; then
        current=$(hyprctl getoption input:touchpad:scroll_method 2>/dev/null | grep "str:" | awk '{print $2}')
        [ -z "$current" ] && current="2fg"
    else
        current=$(_input_get "tp_scroll_method" "2fg")
    fi

    local choice
    choice=$(_rofi_select "  Scroll Method ($current)" \
        "2fg  (two-finger scroll)" \
        "edge  (edge scroll)" \
        "on_button_down  (button + drag)" \
        "no_scroll  (disabled)")
    [ -z "$choice" ] && return

    local val
    val=$(echo "$choice" | awk '{print $1}')

    if [ -n "$WAYLAND_DISPLAY" ]; then
        _input_apply_hypr "input:touchpad:scroll_method" "$val"
    else
        case "$val" in
            2fg)            _xinput_set "libinput Scroll Method Enabled" "1 0 0" ;;
            edge)           _xinput_set "libinput Scroll Method Enabled" "0 1 0" ;;
            on_button_down) _xinput_set "libinput Scroll Method Enabled" "0 0 1" ;;
            no_scroll)      _xinput_set "libinput Scroll Method Enabled" "0 0 0" ;;
        esac
    fi
    _input_save "tp_scroll_method" "$val"
    _notify "Scroll method: $val"
}

# ── Touchpad: Click Method ──
_tp_click_method() {
    local current
    if [ -n "$WAYLAND_DISPLAY" ]; then
        current=$(hyprctl getoption input:touchpad:clickfinger_behavior 2>/dev/null | grep "int:" | awk '{print $2}')
        [ "$current" = "1" ] && current="clickfinger" || current="button_areas"
    else
        current=$(_input_get "tp_click_method" "button_areas")
    fi

    local choice
    choice=$(_rofi_select "  Click Method ($current)" \
        "button_areas  (bottom left/right = L/R click)" \
        "clickfinger  (1 finger=L, 2=R, 3=M)")
    [ -z "$choice" ] && return

    local val
    val=$(echo "$choice" | awk '{print $1}')

    if [ -n "$WAYLAND_DISPLAY" ]; then
        [ "$val" = "clickfinger" ] && _input_apply_hypr "input:touchpad:clickfinger_behavior" "1" \
            || _input_apply_hypr "input:touchpad:clickfinger_behavior" "0"
    else
        case "$val" in
            button_areas) _xinput_set "libinput Click Method Enabled" "1 0" ;;
            clickfinger)  _xinput_set "libinput Click Method Enabled" "0 1" ;;
        esac
    fi
    _input_save "tp_click_method" "$val"
    _notify "Click method: $val"
}

# ── Touchpad: Drag ──
_tp_drag() {
    local current label
    if [ -n "$WAYLAND_DISPLAY" ]; then
        current=$(hyprctl getoption input:touchpad:tap-and-drag 2>/dev/null | grep "int:" | awk '{print $2}')
    else
        current=$(_input_get "tap_and_drag" "1")
    fi
    [ "$current" = "1" ] && label="on" || label="off"

    local choice
    choice=$(_rofi_select "  Tap and Drag ($label)" \
        "  Enable (tap+hold to drag)" \
        "  Disable")
    [ -z "$choice" ] && return

    local val
    [[ "$choice" == *"Enable"* ]] && val=1 || val=0

    if [ -n "$WAYLAND_DISPLAY" ]; then
        _input_apply_hypr "input:touchpad:tap-and-drag" "$val"
    else
        _xinput_set "libinput Tapping Drag Enabled" "$val"
    fi
    _input_save "tap_and_drag" "$val"
    [ "$val" = "1" ] && _notify "Tap and drag: on" || _notify "Tap and drag: off"
}

# ══════════════════════════════════════════════════════════════
#   TOUCHPAD GESTURES (libinput-gestures)
# ══════════════════════════════════════════════════════════════

GESTURE_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/gestures.conf"

# All 12 gestures: {2,3,4} fingers × {up,down,left,right}
_GESTURE_KEYS=(
    "swipe_2_up"    "swipe_2_down"  "swipe_2_left"  "swipe_2_right"
    "swipe_3_up"    "swipe_3_down"  "swipe_3_left"  "swipe_3_right"
    "swipe_4_up"    "swipe_4_down"  "swipe_4_left"  "swipe_4_right"
)

_GESTURE_LABELS=(
    "2 fingers ↑"   "2 fingers ↓"   "2 fingers ←"   "2 fingers →"
    "3 fingers ↑"   "3 fingers ↓"   "3 fingers ←"   "3 fingers →"
    "4 fingers ↑"   "4 fingers ↓"   "4 fingers ←"   "4 fingers →"
)

# Default gestures
_GESTURE_DEFAULTS=(
    "volume_up"         "volume_down"       "disabled"          "disabled"
    "workspace_prev"    "workspace_next"    "window_move_left"  "window_move_right"
    "overview"          "window_close"      "window_prev"       "window_next"
)

# Action catalog: id|label|wayland_cmd|xorg_cmd
_gesture_actions() {
    cat <<'ACTIONS'
disabled|  Disabled||
workspace_next|  Workspace next|hyprctl dispatch workspace e+1|i3-msg workspace next
workspace_prev|  Workspace prev|hyprctl dispatch workspace e-1|i3-msg workspace prev
window_close|  Close window|hyprctl dispatch killactive|i3-msg kill
window_fullscreen|  Toggle fullscreen|hyprctl dispatch fullscreen|i3-msg fullscreen toggle
window_float|  Toggle floating|hyprctl dispatch togglefloating|i3-msg floating toggle
window_move_left|  Move window left|hyprctl dispatch movewindow l|i3-msg move left
window_move_right|  Move window right|hyprctl dispatch movewindow r|i3-msg move right
window_move_up|  Move window up|hyprctl dispatch movewindow u|i3-msg move up
window_move_down|  Move window down|hyprctl dispatch movewindow d|i3-msg move down
window_next|  Next window|hyprctl dispatch cyclenext|i3-msg focus right
window_prev|  Prev window|hyprctl dispatch cyclenext prev|i3-msg focus left
window_minimize|  Minimize|hyprctl dispatch movetospecialworkspace minimize|i3-msg move scratchpad
overview|  Overview / App switcher|rofi -show window -config ~/.config/rofi/config.rasi|rofi -show window -config ~/.config/rofi/config.rasi
launcher|  App launcher|rofi -show drun -config ~/.config/rofi/config.rasi|rofi -show drun -config ~/.config/rofi/config.rasi
volume_up|  Volume up|wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ -l 1.0|wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ -l 1.0
volume_down|  Volume down|wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-|wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
volume_mute|  Toggle mute|wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle|wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
brightness_up|  Brightness up|brightnessctl set +5% -q|brightnessctl set +5% -q
brightness_down|  Brightness down|brightnessctl set 5%- -q|brightnessctl set 5%- -q
screenshot|  Screenshot|grim -g "$(slurp)" ~/Pictures/screenshots/$(date +%Y%m%d_%H%M%S).png|maim -s ~/Pictures/screenshots/$(date +%Y%m%d_%H%M%S).png
play_pause|  Play / Pause|playerctl play-pause|playerctl play-pause
next_track|  Next track|playerctl next|playerctl next
prev_track|  Previous track|playerctl previous|playerctl previous
settings|  Stoa Settings|stoa-settings|stoa-settings
ACTIONS
}

_gesture_get() {
    local key="$1"
    local val
    val=$(grep "^${key}=" "$GESTURE_CONF" 2>/dev/null | cut -d= -f2)
    # Find default
    if [ -z "$val" ]; then
        for i in "${!_GESTURE_KEYS[@]}"; do
            if [ "${_GESTURE_KEYS[$i]}" = "$key" ]; then
                val="${_GESTURE_DEFAULTS[$i]}"
                break
            fi
        done
    fi
    echo "${val:-disabled}"
}

_gesture_set() {
    local key="$1" val="$2"
    mkdir -p "$(dirname "$GESTURE_CONF")"
    touch "$GESTURE_CONF"
    if grep -q "^${key}=" "$GESTURE_CONF" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$GESTURE_CONF"
    else
        echo "${key}=${val}" >> "$GESTURE_CONF"
    fi
}

# Get the label for an action id
_gesture_action_label() {
    local action_id="$1"
    _gesture_actions | while IFS='|' read -r id label _wcmd _xcmd; do
        [ "$id" = "$action_id" ] && echo "$label" && return
    done
}

# Get command for an action id
_gesture_action_cmd() {
    local action_id="$1"
    _gesture_actions | while IFS='|' read -r id _label wcmd xcmd; do
        if [ "$id" = "$action_id" ]; then
            if [ -n "$WAYLAND_DISPLAY" ]; then
                echo "$wcmd"
            else
                echo "$xcmd"
            fi
            return
        fi
    done
}

# Select an action from the catalog
_gesture_pick_action() {
    local gesture_label="$1" current_id="$2"
    local current_label
    current_label=$(_gesture_action_label "$current_id")

    local items=()
    while IFS='|' read -r id label _wcmd _xcmd; do
        if [ "$id" = "$current_id" ]; then
            items+=("${label} ◄")
        else
            items+=("$label")
        fi
    done < <(_gesture_actions)

    local choice
    choice=$(printf '%s\n' "${items[@]}" | "${ROFI[@]}" -p "  $gesture_label")
    [ -z "$choice" ] && return 1

    # Remove current marker
    choice=$(echo "$choice" | sed 's/ ◄$//')

    # Find the action id
    while IFS='|' read -r id label _wcmd _xcmd; do
        if [ "$label" = "$choice" ]; then
            echo "$id"
            return 0
        fi
    done < <(_gesture_actions)
    return 1
}

# Generate libinput-gestures.conf from our config
_gestures_apply() {
    local conf_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
    local out="${conf_dir}/libinput-gestures.conf"

    {
        echo "# Generated by Stoa Linux — do not edit manually"
        echo "# Regenerate via: Super+I → Mouse & Touchpad → Touchpad → Gestures"
        echo ""

        for i in "${!_GESTURE_KEYS[@]}"; do
            local key="${_GESTURE_KEYS[$i]}"
            local action_id
            action_id=$(_gesture_get "$key")
            [ "$action_id" = "disabled" ] && continue

            local cmd
            cmd=$(_gesture_action_cmd "$action_id")
            [ -z "$cmd" ] && continue

            # Parse key: swipe_3_up → "gesture swipe up 3"
            local fingers direction
            fingers=$(echo "$key" | cut -d_ -f2)
            direction=$(echo "$key" | cut -d_ -f3)

            echo "gesture swipe $direction $fingers $cmd"
        done
    } > "$out"

    # Restart libinput-gestures
    if command -v libinput-gestures-setup &>/dev/null; then
        libinput-gestures-setup stop 2>/dev/null
        libinput-gestures-setup start 2>/dev/null
    elif command -v libinput-gestures &>/dev/null; then
        pkill -f libinput-gestures 2>/dev/null
        libinput-gestures &>/dev/null &
        disown
    fi
}

# Configure a single gesture
_gesture_configure() {
    local index="$1"
    local key="${_GESTURE_KEYS[$index]}"
    local label="${_GESTURE_LABELS[$index]}"
    local current_id
    current_id=$(_gesture_get "$key")

    local new_id
    new_id=$(_gesture_pick_action "$label" "$current_id")
    [ $? -ne 0 ] && return

    _gesture_set "$key" "$new_id"
    _gestures_apply

    local new_label
    new_label=$(_gesture_action_label "$new_id")
    _notify "${label}: ${new_label}"
}

# Gestures submenu — shows all 12 with current assignments
_menu_gestures() {
    while true; do
        local items=()
        for i in "${!_GESTURE_KEYS[@]}"; do
            local key="${_GESTURE_KEYS[$i]}"
            local label="${_GESTURE_LABELS[$i]}"
            local action_id action_label
            action_id=$(_gesture_get "$key")
            action_label=$(_gesture_action_label "$action_id")
            # Pad label for alignment
            local padded
            padded=$(printf "%-14s" "$label")
            items+=("  ${padded} → ${action_label}")
        done
        items+=("")
        items+=("  Apply & restart gestures")
        items+=("  Reset to defaults")
        items+=("  Back")

        local choice
        choice=$(printf '%s\n' "${items[@]}" | "${ROFI[@]}" -p "  Gestures")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        if [[ "$choice" == *"Apply"* ]]; then
            _gestures_apply
            _notify "Gestures applied!"
            continue
        fi

        if [[ "$choice" == *"Reset"* ]]; then
            _rofi_confirm "Reset all gestures to defaults?" && {
                rm -f "$GESTURE_CONF"
                _gestures_apply
                _notify "Gestures reset to defaults"
            }
            continue
        fi

        # Find which gesture was selected
        for i in "${!_GESTURE_LABELS[@]}"; do
            if [[ "$choice" == *"${_GESTURE_LABELS[$i]}"* ]]; then
                _gesture_configure "$i"
                break
            fi
        done
    done
}

menu_mouse() {
    while true; do
        local choice
        choice=$(_rofi_select "  Mouse & Touchpad" \
            "  Mouse" \
            "  Touchpad" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *Mouse*)    _menu_mouse_sub ;;
            *Touchpad*) _menu_touchpad_sub ;;
        esac
    done
}

_menu_mouse_sub() {
    while true; do
        local choice
        choice=$(_rofi_select "  Mouse" \
            "  Sensitivity" \
            "  Accel profile" \
            "  Natural scroll" \
            "  Scroll speed" \
            "  Left-handed mode" \
            "  Focus follows mouse" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *Sensitivity*)     _mouse_sensitivity ;;
            *Accel*)           _mouse_accel_profile ;;
            *"Natural scroll"*) _mouse_natural_scroll ;;
            *"Scroll speed"*)  _mouse_scroll_factor ;;
            *Left*)            _mouse_left_handed ;;
            *Focus*)           _mouse_follow ;;
        esac
    done
}

_menu_touchpad_sub() {
    while true; do
        local choice
        choice=$(_rofi_select "  Touchpad" \
            "  Gestures" \
            "  Tap to click" \
            "  Natural scroll" \
            "  Scroll method" \
            "  Click method" \
            "  Tap and drag" \
            "  Disable while typing" \
            "  Sensitivity" \
            "  Accel profile" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *Gestures*)         _menu_gestures ;;
            *"Tap to click"*)   _tp_tap ;;
            *"Natural scroll"*) _tp_natural_scroll ;;
            *"Scroll method"*)  _tp_scroll_method ;;
            *"Click method"*)   _tp_click_method ;;
            *"Tap and drag"*)   _tp_drag ;;
            *"Disable while"*)  _tp_dwt ;;
            *Sensitivity*)      _mouse_sensitivity ;;
            *Accel*)            _mouse_accel_profile ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════
#   NIGHT LIGHT (blue light filter — gammastep)
# ══════════════════════════════════════════════════════════════

NIGHTLIGHT_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/nightlight.conf"

_nightlight_save() {
    local key="$1" val="$2"
    mkdir -p "$(dirname "$NIGHTLIGHT_CONF")"
    [ ! -f "$NIGHTLIGHT_CONF" ] && touch "$NIGHTLIGHT_CONF"
    if grep -q "^${key}=" "$NIGHTLIGHT_CONF" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$NIGHTLIGHT_CONF"
    else
        echo "${key}=${val}" >> "$NIGHTLIGHT_CONF"
    fi
}

_nightlight_get() {
    local key="$1" default="$2"
    if [ -f "$NIGHTLIGHT_CONF" ]; then
        local val
        val=$(grep "^${key}=" "$NIGHTLIGHT_CONF" 2>/dev/null | cut -d= -f2)
        [ -n "$val" ] && echo "$val" && return
    fi
    echo "$default"
}

_nightlight_running() {
    pgrep -x gammastep &>/dev/null && echo "on" || echo "off"
}

_nightlight_toggle() {
    if pgrep -x gammastep &>/dev/null; then
        pkill -x gammastep
        _nightlight_save "ENABLED" "false"
        _notify "Night light: off"
    else
        local temp
        temp=$(_nightlight_get "TEMPERATURE" "4500")
        gammastep -O "$temp" &>/dev/null &
        disown
        _nightlight_save "ENABLED" "true"
        _notify "Night light: on (${temp}K)"
    fi
}

_nightlight_temperature() {
    local current
    current=$(_nightlight_get "TEMPERATURE" "4500")

    local choice
    choice=$(_rofi_select "  Temperature (${current}K)" \
        "  6500K (daylight)" \
        "  5500K (warm white)" \
        "  5000K (soft)" \
        "  4500K (warm)" \
        "  4000K (sunset)" \
        "  3500K (candle)" \
        "  3000K (amber)" \
        "  2500K (deep warm)" \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    local temp
    temp=$(echo "$choice" | grep -oP '\d+(?=K)')
    [ -z "$temp" ] && return

    _nightlight_save "TEMPERATURE" "$temp"

    # Apply immediately if running
    if pgrep -x gammastep &>/dev/null; then
        pkill -x gammastep
        gammastep -O "$temp" &>/dev/null &
        disown
    fi
    _notify "Temperature: ${temp}K"
}

_nightlight_schedule() {
    local mode
    mode=$(_nightlight_get "SCHEDULE" "manual")

    local choice
    choice=$(_rofi_select "  Schedule ($mode)" \
        "  Manual (toggle on/off)" \
        "  Sunset to sunrise (auto)" \
        "  Custom hours" \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    case "$choice" in
        *Manual*)
            _nightlight_save "SCHEDULE" "manual"
            pkill -x gammastep 2>/dev/null
            _notify "Schedule: manual"
            ;;
        *Sunset*)
            _nightlight_save "SCHEDULE" "auto"
            local temp
            temp=$(_nightlight_get "TEMPERATURE" "4500")
            pkill -x gammastep 2>/dev/null
            gammastep -t 6500:"$temp" &>/dev/null &
            disown
            _nightlight_save "ENABLED" "true"
            _notify "Schedule: sunset to sunrise"
            ;;
        *Custom*)
            local start
            start=$(_rofi_input "  Start hour (e.g. 20:00)")
            [ -z "$start" ] && return
            local end
            end=$(_rofi_input "  End hour (e.g. 06:00)")
            [ -z "$end" ] && return
            _nightlight_save "SCHEDULE" "custom"
            _nightlight_save "CUSTOM_START" "$start"
            _nightlight_save "CUSTOM_END" "$end"
            _notify "Schedule: ${start} to ${end}"
            ;;
    esac
}

menu_nightlight() {
    if ! command -v gammastep &>/dev/null; then
        _notify "gammastep not installed (pacman -S gammastep)"
        return
    fi

    while true; do
        local status
        status=$(_nightlight_running)
        local temp
        temp=$(_nightlight_get "TEMPERATURE" "4500")

        local choice
        choice=$(_rofi_select "  Night Light ($status)" \
            "  Toggle night light ($status)" \
            "  Temperature (${temp}K)" \
            "  Schedule" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *Toggle*)      _nightlight_toggle ;;
            *Temperature*) _nightlight_temperature ;;
            *Schedule*)    _nightlight_schedule ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════
#   POWER MANAGEMENT (profiles, idle, suspend)
# ══════════════════════════════════════════════════════════════

_power_current_profile() {
    if command -v powerprofilesctl &>/dev/null; then
        powerprofilesctl get 2>/dev/null || echo "unknown"
    else
        echo "N/A"
    fi
}

_power_set_profile() {
    local choice
    local current
    current=$(_power_current_profile)

    choice=$(_rofi_select "  Profile ($current)" \
        "  Performance" \
        "  Balanced" \
        "  Power saver" \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    local profile
    case "$choice" in
        *Performance*) profile="performance" ;;
        *Balanced*)    profile="balanced" ;;
        *"Power saver"*) profile="power-saver" ;;
    esac

    if command -v powerprofilesctl &>/dev/null; then
        powerprofilesctl set "$profile" 2>/dev/null
        _notify "Power profile: $profile"
    else
        _notify "power-profiles-daemon not installed"
    fi
}

_power_idle_timeout() {
    local current
    if [ -n "$WAYLAND_DISPLAY" ] && command -v hyprctl &>/dev/null; then
        current=$(hyprctl getoption misc:dpms_timeout 2>/dev/null | grep "int:" | awk '{print $2}')
        [ -z "$current" ] || [ "$current" = "0" ] && current="off"
        [ "$current" != "off" ] && current="${current}s"
    else
        current="unknown"
    fi

    local choice
    choice=$(_rofi_select "  Screen off after ($current)" \
        "  1 minute" \
        "  2 minutes" \
        "  5 minutes" \
        "  10 minutes" \
        "  15 minutes" \
        "  30 minutes" \
        "  Never" \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    local seconds
    case "$choice" in
        *"1 minute"*)   seconds=60 ;;
        *"2 minute"*)   seconds=120 ;;
        *"5 minute"*)   seconds=300 ;;
        *"10 minute"*)  seconds=600 ;;
        *"15 minute"*)  seconds=900 ;;
        *"30 minute"*)  seconds=1800 ;;
        *Never*)        seconds=0 ;;
    esac

    if [ -n "$WAYLAND_DISPLAY" ] && command -v hyprctl &>/dev/null; then
        hyprctl keyword misc:dpms_timeout "$seconds" &>/dev/null
        [ "$seconds" -eq 0 ] && _notify "Screen off: never" || _notify "Screen off: $((seconds / 60)) min"
    else
        if [ "$seconds" -eq 0 ]; then
            xset s off -dpms 2>/dev/null
            _notify "Screen off: never"
        else
            xset s "$seconds" dpms "$seconds" "$seconds" "$seconds" 2>/dev/null
            _notify "Screen off: $((seconds / 60)) min"
        fi
    fi
}

_power_auto_suspend() {
    local current
    current=$(systemctl show sleep.target --property=ActiveState 2>/dev/null | cut -d= -f2)
    local idle_delay
    idle_delay=$(gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 2>/dev/null || echo "")

    local choice
    choice=$(_rofi_select "  Auto Suspend" \
        "  Suspend after 15 min" \
        "  Suspend after 30 min" \
        "  Suspend after 1 hour" \
        "  Suspend after 2 hours" \
        "  Disable auto suspend" \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    local minutes
    case "$choice" in
        *"15 min"*)  minutes=15 ;;
        *"30 min"*)  minutes=30 ;;
        *"1 hour"*)  minutes=60 ;;
        *"2 hour"*)  minutes=120 ;;
        *Disable*)   minutes=0 ;;
    esac

    local conf_dir="/etc/systemd/sleep.conf.d"
    if [ "$minutes" -eq 0 ]; then
        sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target 2>/dev/null
        _notify "Auto suspend: disabled"
    else
        sudo systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target 2>/dev/null
        sudo mkdir -p "$conf_dir"
        printf '[Sleep]\nIdleActionSec=%dm\nIdleAction=suspend\n' "$minutes" | sudo tee "$conf_dir/stoa-idle.conf" >/dev/null
        _notify "Auto suspend: ${minutes} min"
    fi
}

_power_battery_info() {
    local bat_path
    bat_path=$(find /sys/class/power_supply -name "BAT*" -maxdepth 1 2>/dev/null | head -1)
    if [ -z "$bat_path" ]; then
        _notify "No battery detected"
        return
    fi

    local status capacity health cycles energy_full energy_full_design ac_status
    status=$(cat "$bat_path/status" 2>/dev/null || echo "Unknown")
    capacity=$(cat "$bat_path/capacity" 2>/dev/null || echo "?")
    energy_full=$(cat "$bat_path/energy_full" 2>/dev/null || cat "$bat_path/charge_full" 2>/dev/null || echo "0")
    energy_full_design=$(cat "$bat_path/energy_full_design" 2>/dev/null || cat "$bat_path/charge_full_design" 2>/dev/null || echo "0")
    cycles=$(cat "$bat_path/cycle_count" 2>/dev/null || echo "N/A")

    health="N/A"
    if [ "$energy_full_design" -gt 0 ] 2>/dev/null; then
        health="$((energy_full * 100 / energy_full_design))%"
    fi

    ac_status="Unplugged"
    for ac in /sys/class/power_supply/AC* /sys/class/power_supply/ADP*; do
        [ -f "$ac/online" ] && [ "$(cat "$ac/online" 2>/dev/null)" = "1" ] && ac_status="Plugged in"
    done

    _rofi_select "  Battery Info" \
        "  Status: $status" \
        "  Charge: ${capacity}%" \
        "  Health: $health" \
        "  Cycles: $cycles" \
        "  AC: $ac_status" \
        "  Back" >/dev/null
}

menu_power_mgmt() {
    while true; do
        local profile
        profile=$(_power_current_profile)

        local choice
        choice=$(_rofi_select "  Power Management" \
            "  Power profile ($profile)" \
            "  Screen off timeout" \
            "  Auto suspend" \
            "  Battery info" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *"Power profile"*)  _power_set_profile ;;
            *"Screen off"*)     _power_idle_timeout ;;
            *"Auto suspend"*)   _power_auto_suspend ;;
            *Battery*)          _power_battery_info ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════
#   KEYBOARD (layout, repeat, Caps Lock behavior)
# ══════════════════════════════════════════════════════════════

_kb_current_layout() {
    if [ -n "$WAYLAND_DISPLAY" ] && command -v hyprctl &>/dev/null; then
        hyprctl getoption input:kb_layout 2>/dev/null | grep "str:" | awk '{print $2}'
    else
        setxkbmap -query 2>/dev/null | grep layout | awk '{print $2}'
    fi
}

_kb_layout() {
    local current
    current=$(_kb_current_layout)

    local choice
    choice=$(_rofi_select "  Layout ($current)" \
        "  us (English US)" \
        "  br (Portuguese BR)" \
        "  gb (English UK)" \
        "  de (German)" \
        "  fr (French)" \
        "  es (Spanish)" \
        "  it (Italian)" \
        "  pt (Portuguese)" \
        "  ru (Russian)" \
        "  jp (Japanese)" \
        "  kr (Korean)" \
        "  cn (Chinese)" \
        "  ar (Arabic)" \
        "  Custom..." \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    local layout
    if [[ "$choice" == *"Custom"* ]]; then
        layout=$(_rofi_input "  Layout code (e.g. latam)")
        [ -z "$layout" ] && return
    else
        layout=$(echo "$choice" | grep -oP '^\s*\S+\s+\K\S+' | tr -d '()')
        # Extract the code before the parenthesis
        layout=$(echo "$choice" | awk '{print $2}')
    fi

    if [ -n "$WAYLAND_DISPLAY" ] && command -v hyprctl &>/dev/null; then
        hyprctl keyword input:kb_layout "$layout" &>/dev/null
        _notify "Keyboard layout: $layout"
    else
        setxkbmap "$layout" 2>/dev/null
        _notify "Keyboard layout: $layout"
    fi
}

_kb_repeat_rate() {
    local current_rate current_delay
    if [ -n "$WAYLAND_DISPLAY" ] && command -v hyprctl &>/dev/null; then
        current_rate=$(hyprctl getoption input:repeat_rate 2>/dev/null | grep "int:" | awk '{print $2}')
        current_delay=$(hyprctl getoption input:repeat_delay 2>/dev/null | grep "int:" | awk '{print $2}')
    else
        current_rate="?"
        current_delay="?"
    fi

    local choice
    choice=$(_rofi_select "  Repeat (rate:${current_rate} delay:${current_delay}ms)" \
        "  Slow (rate 15, delay 600ms)" \
        "  Normal (rate 25, delay 400ms)" \
        "  Fast (rate 40, delay 300ms)" \
        "  Very fast (rate 50, delay 200ms)" \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    local rate delay
    case "$choice" in
        *Slow*)      rate=15; delay=600 ;;
        *Normal*)    rate=25; delay=400 ;;
        *Fast*)      rate=40; delay=300 ;;
        *"Very fast"*) rate=50; delay=200 ;;
    esac

    if [ -n "$WAYLAND_DISPLAY" ] && command -v hyprctl &>/dev/null; then
        hyprctl keyword input:repeat_rate "$rate" &>/dev/null
        hyprctl keyword input:repeat_delay "$delay" &>/dev/null
    else
        xset r rate "$delay" "$rate" 2>/dev/null
    fi
    _notify "Repeat: rate $rate, delay ${delay}ms"
}

_kb_capslock_behavior() {
    local choice
    choice=$(_rofi_select "  Caps Lock behavior" \
        "  Default (Caps Lock)" \
        "  Escape (vim-friendly)" \
        "  Ctrl (Emacs-friendly)" \
        "  Backspace" \
        "  Disabled" \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    local opt
    case "$choice" in
        *Default*)    opt="" ;;
        *Escape*)     opt="caps:escape" ;;
        *Ctrl*)       opt="ctrl:nocaps" ;;
        *Backspace*)  opt="caps:backspace" ;;
        *Disabled*)   opt="caps:none" ;;
    esac

    if [ -n "$WAYLAND_DISPLAY" ] && command -v hyprctl &>/dev/null; then
        hyprctl keyword input:kb_options "$opt" &>/dev/null
        _notify "Caps Lock: $(echo "$choice" | sed 's/^[[:space:]]*//' | sed 's/^[^ ]* //')"
    else
        local layout
        layout=$(setxkbmap -query 2>/dev/null | grep layout | awk '{print $2}')
        if [ -n "$opt" ]; then
            setxkbmap "$layout" -option "" -option "$opt" 2>/dev/null
        else
            setxkbmap "$layout" -option "" 2>/dev/null
        fi
        _notify "Caps Lock: $(echo "$choice" | sed 's/^[[:space:]]*//' | sed 's/^[^ ]* //')"
    fi
}

_kb_numlock() {
    local choice
    choice=$(_rofi_select "  NumLock on boot" \
        "  On" \
        "  Off" \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    case "$choice" in
        *On*)
            if [ -n "$WAYLAND_DISPLAY" ] && command -v hyprctl &>/dev/null; then
                hyprctl keyword input:numlock_by_default true &>/dev/null
            else
                numlockx on 2>/dev/null
            fi
            _notify "NumLock on boot: on"
            ;;
        *Off*)
            if [ -n "$WAYLAND_DISPLAY" ] && command -v hyprctl &>/dev/null; then
                hyprctl keyword input:numlock_by_default false &>/dev/null
            else
                numlockx off 2>/dev/null
            fi
            _notify "NumLock on boot: off"
            ;;
    esac
}

menu_keyboard() {
    while true; do
        local layout
        layout=$(_kb_current_layout)

        local choice
        choice=$(_rofi_select "  Keyboard" \
            "  Layout ($layout)" \
            "  Repeat rate & delay" \
            "  Caps Lock behavior" \
            "  NumLock on boot" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *Layout*)     _kb_layout ;;
            *Repeat*)     _kb_repeat_rate ;;
            *Caps*)       _kb_capslock_behavior ;;
            *NumLock*)    _kb_numlock ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════
#   PRINTERS & SCANNERS (CUPS)
# ══════════════════════════════════════════════════════════════

_print_cups_status() {
    if systemctl is-active cups.service &>/dev/null; then
        echo "running"
    elif systemctl is-enabled cups.service &>/dev/null; then
        echo "enabled"
    else
        echo "off"
    fi
}

_print_list() {
    local printers
    printers=$(lpstat -p 2>/dev/null | awk '{print $2}')
    [ -z "$printers" ] && { _notify "No printers found"; return; }

    local default
    default=$(lpstat -d 2>/dev/null | awk '{print $NF}')

    local items=()
    while IFS= read -r p; do
        local status
        status=$(lpstat -p "$p" 2>/dev/null | grep -oP '(idle|printing|disabled)')
        local mark=""
        [ "$p" = "$default" ] && mark=" (default)"
        items+=("  $p — ${status:-unknown}${mark}")
    done <<< "$printers"

    local choice
    choice=$(_rofi_select "  Printers" "${items[@]}" "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    local selected
    selected=$(echo "$choice" | awk '{print $2}')

    local action
    action=$(_rofi_select "  $selected" \
        "  Set as default" \
        "  Print test page" \
        "  Enable" \
        "  Disable" \
        "  Remove" \
        "  Back")
    [ -z "$action" ] || [[ "$action" == *"Back"* ]] && return

    case "$action" in
        *"Set as default"*)
            lpadmin -d "$selected" 2>/dev/null
            _notify "Default printer: $selected"
            ;;
        *"Print test"*)
            lp -d "$selected" /usr/share/cups/data/testprint 2>/dev/null
            _notify "Test page sent to $selected"
            ;;
        *Enable*)
            cupsenable "$selected" 2>/dev/null
            _notify "Printer enabled: $selected"
            ;;
        *Disable*)
            cupsdisable "$selected" 2>/dev/null
            _notify "Printer disabled: $selected"
            ;;
        *Remove*)
            _rofi_confirm "Remove $selected?" && {
                lpadmin -x "$selected" 2>/dev/null
                _notify "Printer removed: $selected"
            }
            ;;
    esac
}

_print_add() {
    if command -v system-config-printer &>/dev/null; then
        system-config-printer &
        disown
        _notify "Opening printer setup..."
    else
        _notify "system-config-printer not installed"
    fi
}

_print_toggle_cups() {
    if systemctl is-active cups.service &>/dev/null; then
        _rofi_confirm "Stop CUPS service?" && {
            sudo systemctl stop cups.service 2>/dev/null
            _notify "CUPS service stopped"
        }
    else
        sudo systemctl enable --now cups.service 2>/dev/null
        _notify "CUPS service started"
    fi
}

_print_queue() {
    local jobs
    jobs=$(lpstat -o 2>/dev/null)
    if [ -z "$jobs" ]; then
        _notify "Print queue is empty"
        return
    fi

    local choice
    choice=$(echo "$jobs" | "${ROFI[@]}" -p "  Print queue")
    [ -z "$choice" ] && return

    local job_id
    job_id=$(echo "$choice" | awk '{print $1}')

    _rofi_confirm "Cancel job $job_id?" && {
        cancel "$job_id" 2>/dev/null
        _notify "Job cancelled: $job_id"
    }
}

_scanner_list() {
    if ! command -v scanimage &>/dev/null; then
        _notify "sane not installed (pacman -S sane)"
        return
    fi

    _notify "Scanning for devices..."
    local scanners
    scanners=$(scanimage -L 2>/dev/null)
    if [ -z "$scanners" ]; then
        _notify "No scanners found"
        return
    fi

    echo "$scanners" | "${ROFI[@]}" -p "  Scanners" >/dev/null
}

menu_printers() {
    if ! command -v lpstat &>/dev/null; then
        _notify "CUPS not installed (pacman -S cups)"
        return
    fi

    while true; do
        local cups_status
        cups_status=$(_print_cups_status)

        local choice
        choice=$(_rofi_select "  Printers & Scanners" \
            "  CUPS service ($cups_status)" \
            "  List printers" \
            "  Add printer" \
            "  Print queue" \
            "  Scanners" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *CUPS*)          _print_toggle_cups ;;
            *"List printer"*) _print_list ;;
            *"Add printer"*) _print_add ;;
            *"Print queue"*) _print_queue ;;
            *Scanners*)      _scanner_list ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════
#   DATE, TIME, REGION & LANGUAGE
# ══════════════════════════════════════════════════════════════

_dt_set_timezone() {
    local current
    current=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "unknown")

    # Common timezones first, then option to search all
    local choice
    choice=$(_rofi_select "  Timezone ($current)" \
        "  America/Sao_Paulo" \
        "  America/New_York" \
        "  America/Chicago" \
        "  America/Denver" \
        "  America/Los_Angeles" \
        "  America/Mexico_City" \
        "  America/Buenos_Aires" \
        "  America/Bogota" \
        "  Europe/London" \
        "  Europe/Berlin" \
        "  Europe/Paris" \
        "  Europe/Madrid" \
        "  Europe/Rome" \
        "  Europe/Lisbon" \
        "  Europe/Moscow" \
        "  Asia/Tokyo" \
        "  Asia/Shanghai" \
        "  Asia/Kolkata" \
        "  Asia/Dubai" \
        "  Asia/Seoul" \
        "  Asia/Singapore" \
        "  Australia/Sydney" \
        "  Pacific/Auckland" \
        "  Search all..." \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    local tz
    if [[ "$choice" == *"Search"* ]]; then
        local query
        query=$(_rofi_input "  Search timezone (e.g. Tokyo)")
        [ -z "$query" ] && return
        tz=$(timedatectl list-timezones 2>/dev/null | grep -i "$query" | "${ROFI[@]}" -p "  Results")
        [ -z "$tz" ] && return
    else
        tz=$(echo "$choice" | sed 's/^[[:space:]]*//' | sed 's/^[^ ]* //')
    fi

    _rofi_confirm "Set timezone to $tz?" && {
        sudo timedatectl set-timezone "$tz" 2>/dev/null
        _notify "Timezone: $tz"
    }
}

_dt_toggle_ntp() {
    local ntp_status
    ntp_status=$(timedatectl show --property=NTP --value 2>/dev/null)

    if [ "$ntp_status" = "yes" ]; then
        _rofi_confirm "Disable auto time sync (NTP)?" && {
            sudo timedatectl set-ntp false 2>/dev/null
            _notify "NTP: disabled"
        }
    else
        sudo timedatectl set-ntp true 2>/dev/null
        _notify "NTP: enabled (auto sync)"
    fi
}

_dt_set_manual_time() {
    local ntp_status
    ntp_status=$(timedatectl show --property=NTP --value 2>/dev/null)
    if [ "$ntp_status" = "yes" ]; then
        _notify "Disable NTP first to set time manually"
        return
    fi

    local date_input
    date_input=$(_rofi_input "  Date (YYYY-MM-DD)")
    [ -z "$date_input" ] && return

    local time_input
    time_input=$(_rofi_input "  Time (HH:MM:SS)")
    [ -z "$time_input" ] && return

    _rofi_confirm "Set to ${date_input} ${time_input}?" && {
        sudo timedatectl set-time "${date_input} ${time_input}" 2>/dev/null
        _notify "Time set: ${date_input} ${time_input}"
    }
}

_dt_24h_toggle() {
    local current
    current=$(gsettings get org.gnome.desktop.interface clock-format 2>/dev/null || echo "'24h'")

    local choice
    choice=$(_rofi_select "  Clock format" \
        "  24-hour (14:30)" \
        "  12-hour (2:30 PM)" \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    case "$choice" in
        *24*)
            gsettings set org.gnome.desktop.interface clock-format '24h' 2>/dev/null
            _notify "Clock: 24-hour"
            ;;
        *12*)
            gsettings set org.gnome.desktop.interface clock-format '12h' 2>/dev/null
            _notify "Clock: 12-hour"
            ;;
    esac
}

_dt_language() {
    local current
    current=$(locale 2>/dev/null | grep "^LANG=" | cut -d= -f2)

    local choice
    choice=$(_rofi_select "  Language ($current)" \
        "  en_US.UTF-8 (English US)" \
        "  pt_BR.UTF-8 (Portuguese BR)" \
        "  pt_PT.UTF-8 (Portuguese PT)" \
        "  es_ES.UTF-8 (Spanish)" \
        "  fr_FR.UTF-8 (French)" \
        "  de_DE.UTF-8 (German)" \
        "  it_IT.UTF-8 (Italian)" \
        "  ja_JP.UTF-8 (Japanese)" \
        "  ko_KR.UTF-8 (Korean)" \
        "  zh_CN.UTF-8 (Chinese Simplified)" \
        "  ru_RU.UTF-8 (Russian)" \
        "  ar_SA.UTF-8 (Arabic)" \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    local locale_val
    locale_val=$(echo "$choice" | awk '{print $2}')

    _rofi_confirm "Set language to ${locale_val}? (requires logout)" && {
        # Enable the locale if not already
        sudo sed -i "s/^#\(${locale_val}\)/\1/" /etc/locale.gen 2>/dev/null
        sudo locale-gen &>/dev/null

        # Set system locale
        sudo localectl set-locale "LANG=${locale_val}" 2>/dev/null
        _notify "Language: ${locale_val} (logout to apply)"
    }
}

menu_datetime() {
    while true; do
        local tz
        tz=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "?")
        local ntp
        ntp=$(timedatectl show --property=NTP --value 2>/dev/null)
        [ "$ntp" = "yes" ] && ntp="on" || ntp="off"
        local now
        now=$(date '+%Y-%m-%d %H:%M')

        local choice
        choice=$(_rofi_select "  Date & Time ($now)" \
            "  Timezone ($tz)" \
            "  Auto sync / NTP ($ntp)" \
            "  Set time manually" \
            "  Clock format (12/24h)" \
            "  Language & Region" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *Timezone*)      _dt_set_timezone ;;
            *NTP*)           _dt_toggle_ntp ;;
            *manually*)      _dt_set_manual_time ;;
            *Clock*)         _dt_24h_toggle ;;
            *Language*)      _dt_language ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════
#   STOA SETTINGS (keybinds, greeting, etc.)
# ══════════════════════════════════════════════════════════════

menu_stoa() {
    while true; do
        # Read current config
        [ -f "$STOA_CONF" ] && source "$STOA_CONF"
        local kb_state="${STOA_SHOW_KEYBINDS:-true}"

        local choice
        choice=$(_rofi_select "  Stoa Config" \
            "  Keybinds in bar ($kb_state)" \
            "  Generate wallpapers" \
            "  Stoic system fetch" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *Keybinds*)
                if [ "$kb_state" = "true" ]; then
                    sed -i 's/^STOA_SHOW_KEYBINDS=.*/STOA_SHOW_KEYBINDS=false/' "$STOA_CONF"
                    _notify "Keybinds bar: hidden"
                else
                    sed -i 's/^STOA_SHOW_KEYBINDS=.*/STOA_SHOW_KEYBINDS=true/' "$STOA_CONF"
                    _notify "Keybinds bar: visible"
                fi
                ;;
            *wallpapers*)
                _notify "Generating wallpapers..."
                stoa-walls 2>/dev/null
                _notify "Wallpapers generated!"
                ;;
            *fetch*)
                kitty -e stoa-fetch &
                disown
                ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════
#   POWER
# ══════════════════════════════════════════════════════════════

menu_power() {
    local choice
    choice=$(_rofi_select "  Power" \
        "  Lock screen" \
        "  Logout" \
        "  Reboot" \
        "  Shutdown" \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    case "$choice" in
        *Lock*)
            if [ -n "$WAYLAND_DISPLAY" ]; then
                hyprlock &
            else
                i3lock-color --blur 5 --ring-color=c49a5c --inside-color=211e19cc \
                    --line-uses-inside --keyhl-color=8a9a6c --bshl-color=b36b5a \
                    --separator-color=6e6a62 --time-color=c49a5c --date-color=d4cfc4aa \
                    --verif-color=8a9a6c --wrong-color=b36b5a --clock \
                    --time-str="%H:%M" --date-str="%A, %d %B" \
                    --time-font="JetBrains Mono" --date-font="JetBrains Mono" &
            fi
            ;;
        *Logout*)
            _rofi_confirm "Logout?" && {
                if [ -n "$WAYLAND_DISPLAY" ]; then
                    hyprctl dispatch exit
                else
                    i3-msg exit
                fi
            }
            ;;
        *Reboot*)
            _rofi_confirm "Reboot?" && systemctl reboot
            ;;
        *Shutdown*)
            _rofi_confirm "Shutdown?" && systemctl poweroff
            ;;
    esac
}

# ══════════════════════════════════════════════════════════════
#   MAIN MENU
# ══════════════════════════════════════════════════════════════

main_menu() {
    while true; do
        local choice
        choice=$(_rofi_select "  Settings" \
            "  Display" \
            "  Audio" \
            "  Night Light" \
            "  Keyboard" \
            "  Mouse & Touchpad" \
            "  Network" \
            "  VPN" \
            "  Firewall" \
            "  Bluetooth" \
            "  Hardware" \
            "  Printers & Scanners" \
            "  Cloud Drive" \
            "  Wallpaper" \
            "  Theme" \
            "  Power Management" \
            "  Date & Time" \
            "  Lock Screen" \
            "  Stoa Config" \
            "  Power")
        [ -z "$choice" ] && exit 0

        case "$choice" in
            *Display*)      menu_display ;;
            *Audio*)        menu_audio ;;
            *"Night Light"*) menu_nightlight ;;
            *Keyboard*)     menu_keyboard ;;
            *"Mouse & Touchpad"*) menu_mouse ;;
            *Network*)      menu_network ;;
            *VPN*)          menu_vpn ;;
            *Firewall*)     menu_firewall ;;
            *Bluetooth*)    menu_bluetooth ;;
            *Hardware*)     menu_hardware ;;
            *"Printers & Scanners"*) menu_printers ;;
            *"Cloud Drive"*) stoa-drive & disown; exit 0 ;;
            *Wallpaper*)    menu_wallpaper ;;
            *Theme*)        menu_theme ;;
            *"Power Management"*) menu_power_mgmt ;;
            *"Date & Time"*) menu_datetime ;;
            *Lock*)         menu_lockscreen ;;
            *Stoa*)         menu_stoa ;;
            *Power*)        menu_power ;;
        esac
    done
}

main_menu
