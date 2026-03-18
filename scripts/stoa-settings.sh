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

menu_display() {
    while true; do
        local choice
        choice=$(_rofi_select "  Display" \
            "  Brightness" \
            "  Resolution" \
            "  Scale" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *Brightness*)  _display_brightness ;;
            *Resolution*)  _display_resolution ;;
            *Scale*)       _display_scale ;;
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
            "  Network" \
            "  VPN" \
            "  Firewall" \
            "  Bluetooth" \
            "  Cloud Drive" \
            "  Wallpaper" \
            "  Theme" \
            "  Lock Screen" \
            "  Stoa Config" \
            "  Power")
        [ -z "$choice" ] && exit 0

        case "$choice" in
            *Display*)      menu_display ;;
            *Audio*)        menu_audio ;;
            *Network*)      menu_network ;;
            *VPN*)          menu_vpn ;;
            *Firewall*)     menu_firewall ;;
            *Bluetooth*)    menu_bluetooth ;;
            *"Cloud Drive"*) stoa-drive & disown; exit 0 ;;
            *Wallpaper*)    menu_wallpaper ;;
            *Theme*)        menu_theme ;;
            *Lock*)         menu_lockscreen ;;
            *Stoa*)         menu_stoa ;;
            *Power*)        menu_power ;;
        esac
    done
}

main_menu
