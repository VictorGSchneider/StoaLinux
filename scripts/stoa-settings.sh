#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Settings                                     ║
# ║  "Order is the first law of heaven." — Marcus Aurelius       ║
# ║                                                              ║
# ║  All-in-one settings panel — native dialogs (yad) plus        ║
# ║  standalone GUI apps for categories that already have one.   ║
# ╚══════════════════════════════════════════════════════════════╝

STOA_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/stoa.conf"
STOA_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/stoa"
WALLDIR="${HOME}/.config/stoa/wallpapers"

# ── Helpers ──

_notify() { notify-send -t 2500 "Stoa Settings" "$1" 2>/dev/null; }

# Break symlink before modifying: copies target content into a real file
# so sed -i doesn't modify the repo source through the symlink
_deref() {
    local f="$1"
    if [ -L "$f" ]; then
        local tmp="${f}.stoa-tmp"
        cp --remove-destination "$(readlink -f "$f")" "$tmp"
        mv "$tmp" "$f"
    fi
}

# ── Hyprland version-aware helper ──
# stoa-doctor writes the detected format to ~/.config/stoa/hyprctl-format
# ("legacy" = grep "int:/float:/str:", "raw" = direct value)
_hyprctl_get() {
    local option="$1" type="${2:-int}"
    local output format

    format=$(cat "${STOA_DIR}/hyprctl-format" 2>/dev/null || echo "legacy")
    output=$(hyprctl getoption "$option" 2>/dev/null)

    case "$format" in
        raw)
            echo "$output" | head -1
            ;;
        *)
            echo "$output" | grep "${type}:" | awk '{print $2}'
            ;;
    esac
}

_yad_select() {
    local prompt="$1"
    shift
    printf '%s\n' "$@" \
        | yad --list --title="$prompt" --column="Option" --no-headers \
              --width=480 --height=440 --separator=''
}

_yad_input() {
    local prompt="$1"
    yad --entry --title="$prompt" --width=380
}

_yad_confirm() {
    local msg="$1"
    yad --question --title="Stoa Settings" --text="$msg"
}

_yad_info() {
    local prompt="$1"
    shift
    printf '%s\n' "$@" \
        | yad --text-info --title="$prompt" --fontname="monospace 11" \
              --width=520 --height=440 --button="Close:0"
}

# Drop-in for the old rofi `"${ROFI[@]}" -p "<title>"` pattern: reads a
# list from stdin (one option per line) and returns the picked line.
_yad_pipe() {
    yad --list --title="$1" --column="Option" --no-headers \
        --width=480 --height=440 --separator=''
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
    choice=$(_yad_select "  Brightness (${pct}%)" \
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

# Resolution, scale, rotation and multi-monitor layout are all handled by
# wdisplays — a standalone GTK GUI for wlr-output-management that covers
# everything the old rofi menu reimplemented over hyprctl/xrandr, with a
# visual drag-and-drop layout editor xrandr-based text menus never had.
_display_layout() {
    if ! command -v wdisplays &>/dev/null; then
        _notify "wdisplays not installed — cannot configure display layout"
        return
    fi
    wdisplays & disown
}

menu_display() {
    while true; do
        local choice
        choice=$(_yad_select "  Display" \
            "  Brightness" \
            "  Layout (resolution, rotation, position, scale)" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *Brightness*) _display_brightness ;;
            *Layout*)     _display_layout ;;
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
    choice=$(_yad_select "  Volume (${status})" \
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
    choice=$(echo "$sinks" | _yad_pipe "  Output device")
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
    choice=$(echo "$sources" | _yad_pipe "  Input device")
    [ -z "$choice" ] && return

    local source_id
    source_id=$(wpctl status 2>/dev/null | sed -n '/Sources:/,/^$/p' | grep "$choice" | grep -oP '\d+' | head -1)
    [ -n "$source_id" ] && wpctl set-default "$source_id" && _notify "Input: $choice"
}

menu_audio() {
    while true; do
        local choice
        choice=$(_yad_select "  Audio" \
            "  Volume" \
            "  Output device" \
            "  Input device" \
            "  Mixer (pwvucontrol)" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *Volume*)  _audio_volume ;;
            *Output*)  _audio_output ;;
            *Input*)   _audio_input ;;
            *Mixer*)
                if command -v pwvucontrol &>/dev/null; then
                    pwvucontrol & disown
                else
                    _notify "pwvucontrol not installed"
                fi
                ;;
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
    choice=$(echo "$networks" | _yad_pipe "  Wi-Fi")
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
    pass=$(_yad_input "  Password for $ssid")
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
    choice=$(echo "$saved" | _yad_pipe "  Forget network")
    [ -z "$choice" ] && return

    _yad_confirm "Forget $choice?" && nmcli con delete "$choice" 2>/dev/null && _notify "Forgot $choice"
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
    choice=$(printf '%s\n' "${lines[@]}" | _yad_pipe "  Saved Networks")
    [ -z "$choice" ] && return

    # Extract network name
    local net_name
    net_name=$(echo "$choice" | sed 's/^  //;s/^  //;s/  (.*//')

    local action
    action=$(_yad_select "  $net_name" \
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
            _yad_confirm "Forget $net_name?" && \
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
        choice=$(_yad_select "  Network ($status)" \
            "  Network info" \
            "  Connect to Wi-Fi" \
            "  Saved networks" \
            "  Disconnect" \
            "  Forget network" \
            "  Toggle Wi-Fi ($wifi_state)" \
            "  Advanced (nm-connection-editor)" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *info*)       _net_info | _yad_pipe "  Network Info" ;;
            *Connect*)    _wifi_connect ;;
            *Saved*)      _wifi_saved ;;
            *Disconnect*) _wifi_disconnect ;;
            *Forget*)     _wifi_forget ;;
            *Toggle*)     _wifi_toggle ;;
            *Advanced*)
                if command -v nm-connection-editor &>/dev/null; then
                    nm-connection-editor & disown
                else
                    _notify "nm-connection-editor not installed"
                fi
                ;;
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
    choice=$(echo "$devices" | _yad_pipe "  Bluetooth")
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
    choice=$(echo "$connected" | _yad_pipe "  Disconnect")
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
    choice=$(printf '%s\n' "${lines[@]}" | _yad_pipe "  Saved Devices")
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
        action=$(_yad_select "  $dev_name" \
            "  Disconnect" \
            "  Forget" \
            "  Back")
    else
        action=$(_yad_select "  $dev_name" \
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
            _yad_confirm "Forget $dev_name?" && {
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
        choice=$(_yad_select "  Bluetooth ($status)" \
            "  Scan and connect" \
            "  Saved devices" \
            "  Disconnect device" \
            "  Toggle Bluetooth ($status)" \
            "  Advanced (blueman-manager)" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *Scan*)       _bt_scan_connect ;;
            *Saved*)      _bt_saved ;;
            *Disconnect*) _bt_disconnect ;;
            *Toggle*)     _bt_toggle ;;
            *Advanced*)
                if command -v blueman-manager &>/dev/null; then
                    blueman-manager & disown
                else
                    _notify "blueman not installed"
                fi
                ;;
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
        choice=$(_yad_select "  Wallpaper" "${items[@]}")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *Generate*)
                _notify "Generating wallpapers..."
                stoa-walls 2>/dev/null
                _notify "Wallpapers generated!"
                ;;
            *custom*)
                local path
                path=$(_yad_input "  Path to wallpaper")
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
    # Noctalia owns the wallpaper layer. Starting a second compositor-level
    # wallpaper tool here would stack a second surface over it.
    # `wallpaper-set` with a single token applies to every output
    # (parseWallpaperSetTokens), and it persists, so the choice survives a
    # restart.
    noctalia msg wallpaper-set "$path" >/dev/null 2>&1
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
    choice=$(echo "$themes" | _yad_pipe "  GTK Theme")
    [ -z "$choice" ] && return

    # Update GTK 3.0
    local gtk3="${HOME}/.config/gtk-3.0/settings.ini"
    if [ -f "$gtk3" ]; then
        _deref "$gtk3"
        sed -i "s/^gtk-theme-name\s*=.*/gtk-theme-name = ${choice}/" "$gtk3"
    fi

    # Update GTK 4.0
    local gtk4="${HOME}/.config/gtk-4.0/settings.ini"
    if [ -f "$gtk4" ]; then
        _deref "$gtk4"
        sed -i "s/^gtk-theme-name\s*=.*/gtk-theme-name = ${choice}/" "$gtk4"
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
    choice=$(echo "$icons" | _yad_pipe "  Icon Theme")
    [ -z "$choice" ] && return

    local gtk3="${HOME}/.config/gtk-3.0/settings.ini"
    [ -f "$gtk3" ] && _deref "$gtk3" && sed -i "s/^gtk-icon-theme-name\s*=.*/gtk-icon-theme-name = ${choice}/" "$gtk3"

    local gtk4="${HOME}/.config/gtk-4.0/settings.ini"
    [ -f "$gtk4" ] && _deref "$gtk4" && sed -i "s/^gtk-icon-theme-name\s*=.*/gtk-icon-theme-name = ${choice}/" "$gtk4"

    command -v gsettings &>/dev/null && gsettings set org.gnome.desktop.interface icon-theme "$choice" 2>/dev/null

    # Noctalia reads QS_ICON_THEME once, at launch (stoa-bar derives it from
    # the GTK setting just written above), so the shell keeps drawing the old
    # theme until it is restarted. Bounce it so the launcher, dock and taskbar
    # follow the picker instead of waiting for the next login.
    if pgrep -x noctalia &>/dev/null; then
        killall noctalia 2>/dev/null
        setsid "${HOME}/.local/bin/stoa-bar" &>/dev/null &
        disown 2>/dev/null
    fi

    _notify "Icons: $choice"
}

_theme_cursor() {
    local cursors
    cursors=$(find /usr/share/icons ~/.local/share/icons ~/.icons -maxdepth 2 -name "cursors" -type d 2>/dev/null | xargs -I{} dirname {} | xargs -I{} basename {} | sort -u)
    [ -z "$cursors" ] && { _notify "No cursor themes found"; return; }

    local choice
    choice=$(echo "$cursors" | _yad_pipe "  Cursor Theme")
    [ -z "$choice" ] && return

    local gtk3="${HOME}/.config/gtk-3.0/settings.ini"
    [ -f "$gtk3" ] && _deref "$gtk3" && sed -i "s/^gtk-cursor-theme-name\s*=.*/gtk-cursor-theme-name = ${choice}/" "$gtk3"

    command -v hyprctl &>/dev/null && hyprctl setcursor "$choice" 24 &>/dev/null

    _notify "Cursor: $choice"
}

_theme_font_size() {
    local choice
    choice=$(_yad_select "  Font Size" \
        "9" "10" "11" "12" "13" "14" "16")
    [ -z "$choice" ] && return

    local gtk3="${HOME}/.config/gtk-3.0/settings.ini"
    # Read current font family from settings.ini
    local current_font
    current_font=$(grep "^gtk-font-name" "$gtk3" 2>/dev/null | sed 's/^[^=]*=\s*//' | sed 's/\s*[0-9]*$//')
    current_font="${current_font:-EB Garamond}"

    [ -f "$gtk3" ] && _deref "$gtk3" && sed -i "s/^gtk-font-name\s*=.*/gtk-font-name = ${current_font} ${choice}/" "$gtk3"

    command -v gsettings &>/dev/null && gsettings set org.gnome.desktop.interface font-name "${current_font} $choice" 2>/dev/null

    _notify "Font size: ${choice}pt"
}

# ── Color Palette Manager ──

STOA_COLORS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/stoa"
STOA_COLORS_FILE="${STOA_COLORS_DIR}/colors.conf"
STOA_DIR_RESOLVED="$(dirname "$(readlink -f "$0")")/.."

# Preset palettes: bg_dark|bg|bg_light|fg|fg_dim|accent|accent2|green|red|blue|grey|name
_color_presets() {
    cat <<'PRESETS'
#1a1714|#211e19|#2d2921|#d4cfc4|#a89f91|#c49a5c|#d4a84b|#8a9a6c|#b36b5a|#5a7a8a|#6e6a62|Stoic (default)
#2e3440|#3b4252|#434c5e|#eceff4|#d8dee9|#88c0d0|#81a1c1|#a3be8c|#bf616a|#5e81ac|#4c566a|Nord
#282a36|#1e1f29|#44475a|#f8f8f2|#6272a4|#bd93f9|#ff79c6|#50fa7b|#ff5555|#8be9fd|#6272a4|Dracula
#1d2021|#282828|#3c3836|#ebdbb2|#a89984|#d79921|#fabd2f|#b8bb26|#fb4934|#458588|#665c54|Gruvbox
#11111b|#1e1e2e|#313244|#cdd6f4|#a6adc8|#cba6f7|#f5c2e7|#a6e3a1|#f38ba8|#89b4fa|#585b70|Catppuccin Mocha
#16161e|#1a1b26|#24283b|#c0caf5|#a9b1d6|#7aa2f7|#bb9af7|#9ece6a|#f7768e|#7dcfff|#565f89|Tokyo Night
#002b36|#073642|#586e75|#fdf6e3|#93a1a1|#b58900|#cb4b16|#859900|#dc322f|#268bd2|#657b83|Solarized Dark
#191724|#1f1d2e|#26233a|#e0def4|#908caa|#c4a7e7|#ebbcba|#31748f|#eb6f92|#9ccfd8|#6e6a86|Rose Pine
#0d1117|#161b22|#21262d|#c9d1d9|#8b949e|#58a6ff|#79c0ff|#3fb950|#f85149|#58a6ff|#484f58|GitHub Dark
#181818|#282828|#383838|#d8d8d8|#b8b8b8|#dc9656|#f7ca88|#a1b56c|#ab4642|#7cafc2|#585858|Base16 Default
PRESETS
}

# Strip '#' from hex
_hex() { echo "${1#\#}"; }

# Convert hex to rgb components for rgba() format
_hex2rgba() {
    local hex=$(_hex "$1")
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))
    echo "${r}, ${g}, ${b}"
}

# Save current palette to conf
_colors_save() {
    local bg_dark="$1" bg="$2" bg_light="$3" fg="$4" fg_dim="$5"
    local accent="$6" accent2="$7" green="$8" red="$9" blue="${10}" grey="${11}"
    mkdir -p "$STOA_COLORS_DIR"
    cat > "$STOA_COLORS_FILE" <<EOF
STOA_BG_DARK="${bg_dark}"
STOA_BG="${bg}"
STOA_BG_LIGHT="${bg_light}"
STOA_FG="${fg}"
STOA_FG_DIM="${fg_dim}"
STOA_ACCENT="${accent}"
STOA_ACCENT2="${accent2}"
STOA_GREEN="${green}"
STOA_RED="${red}"
STOA_BLUE="${blue}"
STOA_GREY="${grey}"
EOF
}

# Load current palette (defaults to Stoic)
_colors_load() {
    C_BG_DARK="#1a1714"; C_BG="#211e19"; C_BG_LIGHT="#2d2921"
    C_FG="#d4cfc4"; C_FG_DIM="#a89f91"
    C_ACCENT="#c49a5c"; C_ACCENT2="#d4a84b"
    C_GREEN="#8a9a6c"; C_RED="#b36b5a"; C_BLUE="#5a7a8a"; C_GREY="#6e6a62"

    if [ -f "$STOA_COLORS_FILE" ]; then
        # shellcheck source=/dev/null
        source "$STOA_COLORS_FILE"
        C_BG_DARK="${STOA_BG_DARK:-$C_BG_DARK}"
        C_BG="${STOA_BG:-$C_BG}"
        C_BG_LIGHT="${STOA_BG_LIGHT:-$C_BG_LIGHT}"
        C_FG="${STOA_FG:-$C_FG}"
        C_FG_DIM="${STOA_FG_DIM:-$C_FG_DIM}"
        C_ACCENT="${STOA_ACCENT:-$C_ACCENT}"
        C_ACCENT2="${STOA_ACCENT2:-$C_ACCENT2}"
        C_GREEN="${STOA_GREEN:-$C_GREEN}"
        C_RED="${STOA_RED:-$C_RED}"
        C_BLUE="${STOA_BLUE:-$C_BLUE}"
        C_GREY="${STOA_GREY:-$C_GREY}"
    fi
}

# Point Noctalia at a palette by name.
#
# Noctalia merges every *.toml in ~/.config/noctalia alphabetically, so
# stoa-custom.toml lands after config.toml and overrides its
# `custom_palette`. GUI edits go to ~/.local/state/noctalia/settings.toml
# and win over both, so that one is rewritten in place when it already
# carries the key — if it does not, the config side is authoritative and
# there is nothing to change there.
_noctalia_select() {
    local name="$1"
    local conf_dir="${HOME}/.config/noctalia"
    local override="${conf_dir}/stoa-custom.toml"
    local state="${HOME}/.local/state/noctalia/settings.toml"

    if [ "$name" = "Stoa" ]; then
        rm -f "$override"
    else
        mkdir -p "$conf_dir"
        cat > "$override" <<EOF
# Written by stoa-settings when a custom palette is applied. Merged after
# config.toml (alphabetical order), so it overrides the custom_palette
# declared there. Removed again by Theme → Color Palette → Reset to Stoic.
[theme]
source         = "custom"
custom_palette = "${name}"
EOF
    fi

    if [ -f "$state" ] && grep -q '^[[:space:]]*custom_palette[[:space:]]*=' "$state"; then
        sed -i "s/^\([[:space:]]*custom_palette[[:space:]]*=[[:space:]]*\).*/\1\"${name}\"/" "$state"
    fi
}

# Apply palette to all config files
_colors_apply() {
    local bg_dark="$1" bg="$2" bg_light="$3" fg="$4" fg_dim="$5"
    local accent="$6" accent2="$7" green="$8" red="$9" blue="${10}" grey="${11}"

    # Stoic defaults (what we're replacing FROM)
    _colors_load
    local old_bg_dark="$C_BG_DARK" old_bg="$C_BG" old_bg_light="$C_BG_LIGHT"
    local old_fg="$C_FG" old_fg_dim="$C_FG_DIM"
    local old_accent="$C_ACCENT" old_accent2="$C_ACCENT2"
    local old_green="$C_GREEN" old_red="$C_RED" old_blue="$C_BLUE" old_grey="$C_GREY"

    # Build sed replacements (case-insensitive hex)
    local -a pairs=(
        "$old_bg_dark|$bg_dark"
        "$old_bg_light|$bg_light"
        "$old_bg|$bg"
        "$old_fg_dim|$fg_dim"
        "$old_fg|$fg"
        "$old_accent2|$accent2"
        "$old_accent|$accent"
        "$old_green|$green"
        "$old_red|$red"
        "$old_blue|$blue"
        "$old_grey|$grey"
    )

    # Files to update
    local -a files=(
        "${HOME}/.config/kitty/kitty.conf"
        "${HOME}/.config/eww/eww.scss"
        "${HOME}/.config/gtk-3.0/gtk.css"
        "${HOME}/.config/gtk-4.0/gtk.css"
    )

    for f in "${files[@]}"; do
        [ -f "$f" ] || continue
        for pair in "${pairs[@]}"; do
            local from="${pair%%|*}" to="${pair##*|}"
            [ "$from" = "$to" ] && continue
            sed -i --follow-symlinks "s/${from}/${to}/gi" "$f"
        done
    done

    # Hyprland: uses rgb(RRGGBB) without '#'. The lua config keeps those
    # literals spelled out in the `colors` table, so the same substitution
    # works there unchanged.
    local hypr="${HOME}/.config/hypr/hyprland.lua"
    if [ -f "$hypr" ]; then
        for pair in "${pairs[@]}"; do
            local from="${pair%%|*}" to="${pair##*|}"
            [ "$from" = "$to" ] && continue
            sed -i --follow-symlinks "s/rgb($(_hex "$from"))/rgb($(_hex "$to"))/gi" "$hypr"
        done
    fi

    # Hyprlock: uses rgba(R, G, B, A) format
    local hyprlock="${HOME}/.config/hypr/hyprlock.conf"
    if [ -f "$hyprlock" ]; then
        for pair in "${pairs[@]}"; do
            local from="${pair%%|*}" to="${pair##*|}"
            [ "$from" = "$to" ] && continue
            local from_rgba=$(_hex2rgba "$from")
            local to_rgba=$(_hex2rgba "$to")
            sed -i --follow-symlinks "s/${from_rgba}/${to_rgba}/g" "$hyprlock"
            # Also replace hex refs (e.g. in <span>)
            sed -i --follow-symlinks "s/${from}/${to}/gi" "$hyprlock"
        done
    fi

    # colors.sh (central reference)
    local colorssh="${STOA_DIR_RESOLVED}/theme/colors.sh"
    if [ -f "$colorssh" ]; then
        for pair in "${pairs[@]}"; do
            local from="${pair%%|*}" to="${pair##*|}"
            [ "$from" = "$to" ] && continue
            sed -i "s/${from}/${to}/gi" "$colorssh"
        done
    fi

    # Noctalia (bar, launcher, notifications, OSD, lock screen)
    #
    # Unlike every other target here, the shipped palette is left alone:
    # ~/.config/noctalia/palettes/Stoa.json is a symlink into the repo and
    # is what "Stoa" means, so overwriting it would rename the palette
    # rather than change it. The custom palette is written beside it as
    # StoaCustom.json, derived from Stoa.json on every apply — never from
    # the previous custom file, so repeated changes cannot accumulate
    # drift — and Noctalia is pointed at whichever of the two applies.
    local pal_dir="${HOME}/.config/noctalia/palettes"
    local shipped="${pal_dir}/Stoa.json"
    if [ -f "$shipped" ]; then
        # The stoic colours Stoa.json is written in, taken from the preset
        # table so there is one source of truth for them.
        local s_bg_dark s_bg s_bg_light s_fg s_fg_dim
        local s_accent s_accent2 s_green s_red s_blue s_grey
        IFS='|' read -r s_bg_dark s_bg s_bg_light s_fg s_fg_dim \
                        s_accent s_accent2 s_green s_red s_blue s_grey _ \
            < <(_color_presets | grep 'Stoic (default)$')

        local -a noct_pairs=(
            "$s_bg_dark|$bg_dark"
            "$s_bg_light|$bg_light"
            "$s_bg|$bg"
            "$s_fg_dim|$fg_dim"
            "$s_fg|$fg"
            "$s_accent2|$accent2"
            "$s_accent|$accent"
            "$s_green|$green"
            "$s_red|$red"
            "$s_blue|$blue"
            "$s_grey|$grey"
        )

        local custom="${pal_dir}/StoaCustom.json"
        local differs=0
        for pair in "${noct_pairs[@]}"; do
            [ "${pair%%|*}" = "${pair##*|}" ] || differs=1
        done

        if [ "$differs" -eq 0 ]; then
            # Back to stoic — drop the generated palette and let the
            # shipped Stoa.json take over again.
            rm -f "$custom"
            _noctalia_select "Stoa"
        else
            cp "$shipped" "$custom"
            for pair in "${noct_pairs[@]}"; do
                local from="${pair%%|*}" to="${pair##*|}"
                [ "$from" = "$to" ] && continue
                sed -i "s/${from}/${to}/gi" "$custom"
            done
            _noctalia_select "StoaCustom"
        fi
    fi

    # Save new palette
    _colors_save "$bg_dark" "$bg" "$bg_light" "$fg" "$fg_dim" \
                 "$accent" "$accent2" "$green" "$red" "$blue" "$grey"

    # Reload live components
    command -v hyprctl &>/dev/null && hyprctl reload &>/dev/null
    pkill -USR1 kitty 2>/dev/null
    disown 2>/dev/null
}

_theme_color_preset() {
    local entries=()
    while IFS='|' read -r _ _ _ _ _ _ _ _ _ _ _ name; do
        entries+=("  ${name}")
    done < <(_color_presets)
    entries+=("  Back")

    local choice
    choice=$(_yad_select "  Color Preset" "${entries[@]}")
    [[ -z "$choice" || "$choice" == *"Back"* ]] && return

    local selected_name="${choice#*  }"
    local line
    line=$(grep "${selected_name}$" < <(_color_presets))
    [ -z "$line" ] && return

    IFS='|' read -r bd bg bl fg fd ac ac2 gr rd bu gy _ <<< "$line"

    if _yad_confirm "Apply '${selected_name}'?"; then
        _colors_apply "$bd" "$bg" "$bl" "$fg" "$fd" "$ac" "$ac2" "$gr" "$rd" "$bu" "$gy"
        _notify "Palette: ${selected_name}\nRestart apps to see full changes."
    fi
}

_theme_color_edit() {
    _colors_load

    while true; do
        local choice
        choice=$(_yad_select "  Edit Colors" \
            "  Background dark: ${C_BG_DARK}" \
            "  Background: ${C_BG}" \
            "  Background light: ${C_BG_LIGHT}" \
            "  Foreground: ${C_FG}" \
            "  Foreground dim: ${C_FG_DIM}" \
            "  Accent (bronze): ${C_ACCENT}" \
            "  Accent 2 (gold): ${C_ACCENT2}" \
            "  Green (olive): ${C_GREEN}" \
            "  Red (terracotta): ${C_RED}" \
            "  Blue (azure): ${C_BLUE}" \
            "  Grey (stone): ${C_GREY}" \
            "  Apply changes" \
            "  Back")
        # Anchored to the end of the label on purpose: an unanchored
        # *"Back"* also matches "  Background …", which closed the menu
        # instead of opening the colour editor.
        [[ -z "$choice" || "$choice" == *Back ]] && return

        case "$choice" in
            *"Apply changes"*)
                if _yad_confirm "Apply custom palette?"; then
                    _colors_apply "$C_BG_DARK" "$C_BG" "$C_BG_LIGHT" "$C_FG" "$C_FG_DIM" \
                                  "$C_ACCENT" "$C_ACCENT2" "$C_GREEN" "$C_RED" "$C_BLUE" "$C_GREY"
                    _notify "Custom palette applied.\nRestart apps to see full changes."
                fi
                ;;
            *"Background dark"*)
                local val; val=$(_yad_input "  Hex color (e.g. #1a1714)")
                if [[ "$val" =~ ^#[0-9a-fA-F]{6}$ ]]; then
                    C_BG_DARK="$val"
                elif [ -n "$val" ]; then
                    _notify "Invalid hex color"
                fi
                ;;
            *"Background light"*)
                local val; val=$(_yad_input "  Hex color (e.g. #2d2921)")
                if [[ "$val" =~ ^#[0-9a-fA-F]{6}$ ]]; then
                    C_BG_LIGHT="$val"
                elif [ -n "$val" ]; then
                    _notify "Invalid hex color"
                fi
                ;;
            *"Background:"*)
                local val; val=$(_yad_input "  Hex color (e.g. #211e19)")
                if [[ "$val" =~ ^#[0-9a-fA-F]{6}$ ]]; then
                    C_BG="$val"
                elif [ -n "$val" ]; then
                    _notify "Invalid hex color"
                fi
                ;;
            *"Foreground dim"*)
                local val; val=$(_yad_input "  Hex color (e.g. #a89f91)")
                if [[ "$val" =~ ^#[0-9a-fA-F]{6}$ ]]; then
                    C_FG_DIM="$val"
                elif [ -n "$val" ]; then
                    _notify "Invalid hex color"
                fi
                ;;
            *"Foreground:"*)
                local val; val=$(_yad_input "  Hex color (e.g. #d4cfc4)")
                if [[ "$val" =~ ^#[0-9a-fA-F]{6}$ ]]; then
                    C_FG="$val"
                elif [ -n "$val" ]; then
                    _notify "Invalid hex color"
                fi
                ;;
            *"Accent (bronze)"*)
                local val; val=$(_yad_input "  Hex color (e.g. #c49a5c)")
                if [[ "$val" =~ ^#[0-9a-fA-F]{6}$ ]]; then
                    C_ACCENT="$val"
                elif [ -n "$val" ]; then
                    _notify "Invalid hex color"
                fi
                ;;
            *"Accent 2 (gold)"*)
                local val; val=$(_yad_input "  Hex color (e.g. #d4a84b)")
                if [[ "$val" =~ ^#[0-9a-fA-F]{6}$ ]]; then
                    C_ACCENT2="$val"
                elif [ -n "$val" ]; then
                    _notify "Invalid hex color"
                fi
                ;;
            *"Green (olive)"*)
                local val; val=$(_yad_input "  Hex color (e.g. #8a9a6c)")
                if [[ "$val" =~ ^#[0-9a-fA-F]{6}$ ]]; then
                    C_GREEN="$val"
                elif [ -n "$val" ]; then
                    _notify "Invalid hex color"
                fi
                ;;
            *"Red (terracotta)"*)
                local val; val=$(_yad_input "  Hex color (e.g. #b36b5a)")
                if [[ "$val" =~ ^#[0-9a-fA-F]{6}$ ]]; then
                    C_RED="$val"
                elif [ -n "$val" ]; then
                    _notify "Invalid hex color"
                fi
                ;;
            *"Blue (azure)"*)
                local val; val=$(_yad_input "  Hex color (e.g. #5a7a8a)")
                if [[ "$val" =~ ^#[0-9a-fA-F]{6}$ ]]; then
                    C_BLUE="$val"
                elif [ -n "$val" ]; then
                    _notify "Invalid hex color"
                fi
                ;;
            *"Grey (stone)"*)
                local val; val=$(_yad_input "  Hex color (e.g. #6e6a62)")
                if [[ "$val" =~ ^#[0-9a-fA-F]{6}$ ]]; then
                    C_GREY="$val"
                elif [ -n "$val" ]; then
                    _notify "Invalid hex color"
                fi
                ;;
        esac
    done
}

_theme_color_current() {
    _colors_load
    _yad_select "  Current Palette" \
        "  bg dark:     ${C_BG_DARK}" \
        "  bg:          ${C_BG}" \
        "  bg light:    ${C_BG_LIGHT}" \
        "  fg:          ${C_FG}" \
        "  fg dim:      ${C_FG_DIM}" \
        "  accent:      ${C_ACCENT}" \
        "  accent 2:    ${C_ACCENT2}" \
        "  green:       ${C_GREEN}" \
        "  red:         ${C_RED}" \
        "  blue:        ${C_BLUE}" \
        "  grey:        ${C_GREY}" \
        "  Back"
}

menu_colors() {
    while true; do
        local choice
        choice=$(_yad_select "  Color Palette" \
            "  Apply Preset" \
            "  Edit Colors" \
            "  View Current Palette" \
            "  Reset to Stoic (default)" \
            "  Back")
        [[ -z "$choice" || "$choice" == *"Back"* ]] && return

        case "$choice" in
            *"Apply Preset"*)       _theme_color_preset ;;
            *"Edit Colors"*)        _theme_color_edit ;;
            *"View Current"*)       _theme_color_current ;;
            *"Reset to Stoic"*)
                if _yad_confirm "Reset to Stoic palette?"; then
                    _colors_apply "#1a1714" "#211e19" "#2d2921" "#d4cfc4" "#a89f91" \
                                  "#c49a5c" "#d4a84b" "#8a9a6c" "#b36b5a" "#5a7a8a" "#6e6a62"
                    _notify "Palette reset to Stoic.\nRestart apps to see full changes."
                fi
                ;;
        esac
    done
}

menu_theme() {
    while true; do
        local choice
        choice=$(_yad_select "  Theme" \
            "  Color Palette" \
            "  GTK Theme" \
            "  Icon Theme" \
            "  Cursor Theme" \
            "  Font Size" \
            "  Advanced (nwg-look)" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *Color*)  menu_colors ;;
            *GTK*)    _theme_gtk ;;
            *Icon*)   _theme_icons ;;
            *Cursor*) _theme_cursor ;;
            *Font*)   _theme_font_size ;;
            *Advanced*)
                if command -v nwg-look &>/dev/null; then
                    nwg-look & disown
                else
                    _notify "nwg-look not installed"
                fi
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
    countries=$(_yad_select "  Country" \
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
    choice=$(_yad_select "  Kill Switch" \
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
        choice=$(_yad_select "  VPN ($status)" \
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
                echo "$details" | _yad_pipe "  VPN Status"
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
        if _yad_confirm "Block port ${port}/${proto}?"; then
            stoa-firewall deny "$port" "$proto" 2>/dev/null
            _notify "Port ${port}/${proto} blocked"
        fi
    else
        # Currently blocked → allow it
        if _yad_confirm "Allow port ${port}/${proto}?"; then
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
        choice=$(_yad_select "  Firewall ($status)" \
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
                port_choice=$(_fw_ports_list | _yad_pipe "  Ports (tap to toggle)")
                [ -n "$port_choice" ] && _fw_toggle_port "$port_choice"
                ;;
            *"Allow a port"*)
                local port_input
                port_input=$(_yad_input "  Port to allow (e.g. 8080)")
                [ -z "$port_input" ] && continue
                local proto_choice
                proto_choice=$(_yad_select "  Protocol" "tcp" "udp")
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
                block_choice=$(cat "$WHITELIST" | _yad_pipe "  Remove from whitelist")
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
                _yad_confirm "Disable firewall? All ports will be open." && {
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
    if command -v hyprctl &>/dev/null; then
        local tap nat_scroll speed
        tap=$(_hyprctl_get input:touchpad:tap int)
        nat_scroll=$(_hyprctl_get input:touchpad:natural_scroll int)
        speed=$(_hyprctl_get input:sensitivity float)
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
    if command -v hyprctl &>/dev/null; then
        layout=$(_hyprctl_get input:kb_layout str)
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
        choice=$(_yad_select "  Hardware" \
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
                } | _yad_pipe "  Hardware"
                ;;
            *CPU*)              _hw_cpu | _yad_pipe "  CPU" ;;
            *GPU*)              _hw_gpu | _yad_pipe "  GPU" ;;
            *Memory*)           _hw_memory | _yad_pipe "  Memory" ;;
            *Disks*)            _hw_disks | _yad_pipe "  Disks" ;;
            *Battery*)          _hw_battery | _yad_pipe "  Battery" ;;
            *USB*)              _hw_usb | _yad_pipe "  USB" ;;
            *"Network adapt"*)  _hw_network | _yad_pipe "  Network Adapters" ;;
            *Audio*)            _hw_audio | _yad_pipe "  Audio" ;;
            *Camera*)           _hw_camera | _yad_pipe "  Camera" ;;
            *Input*)            _hw_input | _yad_pipe "  Input Devices" ;;
            *Sensors*)          _hw_sensors | _yad_pipe "  Sensors" ;;
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

# ── Sensitivity / Speed ──
_mouse_sensitivity() {
    local current
    current=$(_hyprctl_get input:sensitivity float)

    local choice
    choice=$(_yad_select "  Sensitivity ($current)" \
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

    _input_apply_hypr "input:sensitivity" "$val"
    _input_save "sensitivity" "$val"
    _notify "Sensitivity: $val"
}

# ── Acceleration Profile ──
_mouse_accel_profile() {
    local current
    current=$(_hyprctl_get input:accel_profile str)
    [ -z "$current" ] && current="(default)"

    local choice
    choice=$(_yad_select "  Accel Profile ($current)" \
        "adaptive  (accelerates with speed)" \
        "flat  (constant speed, no accel)" \
        "custom")
    [ -z "$choice" ] && return

    local val
    val=$(echo "$choice" | awk '{print $1}')

    _input_apply_hypr "input:accel_profile" "$val"
    _input_save "accel_profile" "$val"
    _notify "Accel profile: $val"
}

# ── Scroll Direction ──
_mouse_natural_scroll() {
    local current label
    current=$(_hyprctl_get input:natural_scroll int)
    [ "$current" = "1" ] || [ "$current" = "true" ] && label="on" || label="off"

    local choice
    choice=$(_yad_select "  Natural Scroll ($label)" \
        "  Enable (scroll follows content)" \
        "  Disable (traditional)")
    [ -z "$choice" ] && return

    local val
    [[ "$choice" == *"Enable"* ]] && val=1 || val=0

    _input_apply_hypr "input:natural_scroll" "$val"
    _input_save "natural_scroll" "$val"
    [ "$val" = "1" ] && _notify "Natural scroll: on" || _notify "Natural scroll: off"
}

# ── Scroll Speed (Hyprland) ──
_mouse_scroll_factor() {
    local current
    current=$(_hyprctl_get input:scroll_factor float)
    [ -z "$current" ] && current="1.0"

    local choice
    choice=$(_yad_select "  Scroll Speed ($current)" \
        "0.5  (slow)" \
        "0.75" \
        "1.0  (default)" \
        "1.5" \
        "2.0  (fast)" \
        "3.0  (very fast)")
    [ -z "$choice" ] && return

    local val
    val=$(echo "$choice" | awk '{print $1}')

    _input_apply_hypr "input:scroll_factor" "$val"
    _input_save "scroll_factor" "$val"
    _notify "Scroll speed: $val"
}

# ── Left-handed Mode ──
_mouse_left_handed() {
    local current label
    current=$(_hyprctl_get input:left_handed int)
    [ "$current" = "1" ] && label="on" || label="off"

    local choice
    choice=$(_yad_select "  Left-handed ($label)" \
        "  Enable (swap left/right buttons)" \
        "  Disable (right-handed)")
    [ -z "$choice" ] && return

    local val
    [[ "$choice" == *"Enable"* ]] && val=1 || val=0

    _input_apply_hypr "input:left_handed" "$val"
    _input_save "left_handed" "$val"
    [ "$val" = "1" ] && _notify "Left-handed: on" || _notify "Left-handed: off"
}

# ── Follow Mouse (Hyprland focus policy) ──
_mouse_follow() {
    local current
    current=$(_hyprctl_get input:follow_mouse int)
    [ -z "$current" ] && current="1"

    local choice
    choice=$(_yad_select "  Focus follows mouse ($current)" \
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
    current=$(_hyprctl_get input:touchpad:tap-to-click int)
    [ "$current" = "1" ] && label="on" || label="off"

    local choice
    choice=$(_yad_select "  Tap to Click ($label)" \
        "  Enable" \
        "  Disable")
    [ -z "$choice" ] && return

    local val
    [[ "$choice" == *"Enable"* ]] && val=1 || val=0

    _input_apply_hypr "input:touchpad:tap-to-click" "$val"
    _input_save "tap_to_click" "$val"
    [ "$val" = "1" ] && _notify "Tap to click: on" || _notify "Tap to click: off"
}

# ── Touchpad: Natural Scroll ──
_tp_natural_scroll() {
    local current label
    current=$(_hyprctl_get input:touchpad:natural_scroll int)
    [ "$current" = "1" ] || [ "$current" = "true" ] && label="on" || label="off"

    local choice
    choice=$(_yad_select "  TP Natural Scroll ($label)" \
        "  Enable (scroll follows content)" \
        "  Disable (traditional)")
    [ -z "$choice" ] && return

    local val
    [[ "$choice" == *"Enable"* ]] && val=1 || val=0

    _input_apply_hypr "input:touchpad:natural_scroll" "$val"
    _input_save "tp_natural_scroll" "$val"
    [ "$val" = "1" ] && _notify "TP natural scroll: on" || _notify "TP natural scroll: off"
}

# ── Touchpad: Disable While Typing ──
_tp_dwt() {
    local current label
    current=$(_hyprctl_get input:touchpad:disable_while_typing int)
    [ "$current" = "1" ] && label="on" || label="off"

    local choice
    choice=$(_yad_select "  Disable while typing ($label)" \
        "  Enable (prevents accidental touches)" \
        "  Disable")
    [ -z "$choice" ] && return

    local val
    [[ "$choice" == *"Enable"* ]] && val=1 || val=0

    _input_apply_hypr "input:touchpad:disable_while_typing" "$val"
    _input_save "dwt" "$val"
    [ "$val" = "1" ] && _notify "Disable while typing: on" || _notify "Disable while typing: off"
}

# ── Touchpad: Scroll Method ──
_tp_scroll_method() {
    local current
    current=$(_hyprctl_get input:touchpad:scroll_method str)
    [ -z "$current" ] && current="2fg"

    local choice
    choice=$(_yad_select "  Scroll Method ($current)" \
        "2fg  (two-finger scroll)" \
        "edge  (edge scroll)" \
        "on_button_down  (button + drag)" \
        "no_scroll  (disabled)")
    [ -z "$choice" ] && return

    local val
    val=$(echo "$choice" | awk '{print $1}')

    _input_apply_hypr "input:touchpad:scroll_method" "$val"
    _input_save "tp_scroll_method" "$val"
    _notify "Scroll method: $val"
}

# ── Touchpad: Click Method ──
_tp_click_method() {
    local current
    current=$(_hyprctl_get input:touchpad:clickfinger_behavior int)
    [ "$current" = "1" ] && current="clickfinger" || current="button_areas"

    local choice
    choice=$(_yad_select "  Click Method ($current)" \
        "button_areas  (bottom left/right = L/R click)" \
        "clickfinger  (1 finger=L, 2=R, 3=M)")
    [ -z "$choice" ] && return

    local val
    val=$(echo "$choice" | awk '{print $1}')

    [ "$val" = "clickfinger" ] && _input_apply_hypr "input:touchpad:clickfinger_behavior" "1" \
        || _input_apply_hypr "input:touchpad:clickfinger_behavior" "0"
    _input_save "tp_click_method" "$val"
    _notify "Click method: $val"
}

# ── Touchpad: Drag ──
_tp_drag() {
    local current label
    current=$(_hyprctl_get input:touchpad:tap-and-drag int)
    [ "$current" = "1" ] && label="on" || label="off"

    local choice
    choice=$(_yad_select "  Tap and Drag ($label)" \
        "  Enable (tap+hold to drag)" \
        "  Disable")
    [ -z "$choice" ] && return

    local val
    [[ "$choice" == *"Enable"* ]] && val=1 || val=0

    _input_apply_hypr "input:touchpad:tap-and-drag" "$val"
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

# Action catalog: id|label|cmd
_gesture_actions() {
    cat <<'ACTIONS'
disabled|  Disabled|
workspace_next|  Workspace next|hyprctl dispatch workspace e+1
workspace_prev|  Workspace prev|hyprctl dispatch workspace e-1
window_close|  Close window|hyprctl dispatch killactive
window_fullscreen|  Toggle fullscreen|hyprctl dispatch fullscreen
window_float|  Toggle floating|hyprctl dispatch togglefloating
window_move_left|  Move window left|hyprctl dispatch movewindow l
window_move_right|  Move window right|hyprctl dispatch movewindow r
window_move_up|  Move window up|hyprctl dispatch movewindow u
window_move_down|  Move window down|hyprctl dispatch movewindow d
window_next|  Next window|hyprctl dispatch cyclenext
window_prev|  Prev window|hyprctl dispatch cyclenext prev
window_minimize|  Minimize|hyprctl dispatch movetospecialworkspace minimize
overview|  Overview / App switcher|hyprswitch gui --mod-key ALT --key Tab --close mod-key-release --max-switch-offset 9 --hide-active-window-border && hyprswitch dispatch
launcher|  App launcher|noctalia msg panel-toggle launcher
volume_up|  Volume up|wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ -l 1.0
volume_down|  Volume down|wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
volume_mute|  Toggle mute|wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
brightness_up|  Brightness up|brightnessctl set +5% -q
brightness_down|  Brightness down|brightnessctl set 5%- -q
screenshot|  Screenshot|grim -g "$(slurp)" ~/Pictures/screenshots/$(date +%Y%m%d_%H%M%S).png
play_pause|  Play / Pause|playerctl play-pause
next_track|  Next track|playerctl next
prev_track|  Previous track|playerctl previous
settings|  Stoa Settings|stoa-settings
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
    _gesture_actions | while IFS='|' read -r id label _cmd; do
        [ "$id" = "$action_id" ] && echo "$label" && return
    done
}

# Get command for an action id
_gesture_action_cmd() {
    local action_id="$1"
    _gesture_actions | while IFS='|' read -r id _label cmd; do
        if [ "$id" = "$action_id" ]; then
            echo "$cmd"
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
    while IFS='|' read -r id label _cmd; do
        if [ "$id" = "$current_id" ]; then
            items+=("${label} ◄")
        else
            items+=("$label")
        fi
    done < <(_gesture_actions)

    local choice
    choice=$(printf '%s\n' "${items[@]}" | _yad_pipe "  $gesture_label")
    [ -z "$choice" ] && return 1

    # Remove current marker
    choice=$(echo "$choice" | sed 's/ ◄$//')

    # Find the action id
    while IFS='|' read -r id label _cmd; do
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
        echo "# Regenerate via: Super+S → Mouse & Touchpad → Touchpad → Gestures"
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
        choice=$(printf '%s\n' "${items[@]}" | _yad_pipe "  Gestures")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        if [[ "$choice" == *"Apply"* ]]; then
            _gestures_apply
            _notify "Gestures applied!"
            continue
        fi

        if [[ "$choice" == *"Reset"* ]]; then
            _yad_confirm "Reset all gestures to defaults?" && {
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
        choice=$(_yad_select "  Mouse & Touchpad" \
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

# ── DPI (via libratbag / ratbagctl) ──

_ratbag_available() {
    command -v ratbagctl &>/dev/null
}

_ratbag_device() {
    ratbagctl list 2>/dev/null | head -1 | cut -d: -f1
}

_mouse_dpi() {
    if ! _ratbag_available; then
        _notify "ratbagctl not installed.\nsudo pacman -S libratbag"
        return
    fi

    local device
    device=$(_ratbag_device)
    if [ -z "$device" ]; then
        _notify "No configurable mouse found.\nMake sure ratbagd is running:\nsudo systemctl enable --now ratbagd"
        return
    fi

    # Get current DPI
    local current
    current=$(ratbagctl "$device" dpi get 2>/dev/null | grep -oP '\d+' | head -1)
    [ -z "$current" ] && current="?"

    local choice
    choice=$(_yad_select "  DPI ($current)" \
        "  400  (low — precision/sniping)" \
        "  800  (default for many mice)" \
        "  1200" \
        "  1600  (common for gaming)" \
        "  2400" \
        "  3200  (high — fast movement)" \
        "  4800" \
        "  6400  (very high)" \
        "  Custom..." \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    local val
    if [[ "$choice" == *"Custom"* ]]; then
        val=$(_yad_input "  DPI value (100–25600)")
        [ -z "$val" ] && return
        # Validate numeric
        if ! [[ "$val" =~ ^[0-9]+$ ]] || [ "$val" -lt 100 ] || [ "$val" -gt 25600 ]; then
            _notify "Invalid DPI: $val (must be 100–25600)"
            return
        fi
    else
        val=$(echo "$choice" | awk '{print $2}')
    fi

    ratbagctl "$device" dpi set "$val" 2>/dev/null
    _input_save "mouse_dpi" "$val"
    _notify "DPI: $val"
}

# ── Polling Rate (via libratbag / ratbagctl) ──

_mouse_polling_rate() {
    if ! _ratbag_available; then
        _notify "ratbagctl not installed.\nsudo pacman -S libratbag"
        return
    fi

    local device
    device=$(_ratbag_device)
    if [ -z "$device" ]; then
        _notify "No configurable mouse found."
        return
    fi

    # Get current report rate
    local current
    current=$(ratbagctl "$device" rate get 2>/dev/null | grep -oP '\d+' | head -1)
    [ -z "$current" ] && current="?"

    local choice
    choice=$(_yad_select "  Polling Rate (${current}Hz)" \
        "  125 Hz  (8ms — low)" \
        "  250 Hz  (4ms)" \
        "  500 Hz  (2ms — balanced)" \
        "  1000 Hz  (1ms — gaming)" \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    local val
    val=$(echo "$choice" | awk '{print $2}')

    ratbagctl "$device" rate set "$val" 2>/dev/null
    _input_save "mouse_polling_rate" "$val"
    _notify "Polling rate: ${val}Hz"
}

# ── DPI Profiles (multiple DPI stages) ──

_mouse_dpi_profiles() {
    if ! _ratbag_available; then
        _notify "ratbagctl not installed.\nsudo pacman -S libratbag"
        return
    fi

    local device
    device=$(_ratbag_device)
    if [ -z "$device" ]; then
        _notify "No configurable mouse found."
        return
    fi

    # Read current profiles
    local profiles
    profiles=$(ratbagctl "$device" dpi get 2>/dev/null)

    local choice
    choice=$(_yad_select "  DPI Profiles" \
        "  View current profiles" \
        "  Gaming preset (400 / 800 / 1600)" \
        "  Productivity preset (800 / 1200 / 2400)" \
        "  High-res preset (1600 / 3200 / 6400)" \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    case "$choice" in
        *"View"*)
            local info
            info=$(ratbagctl "$device" dpi get 2>/dev/null)
            echo "$info" | _yad_pipe "  Current DPI" >/dev/null
            ;;
        *Gaming*)
            ratbagctl "$device" dpi set 400 0 2>/dev/null
            ratbagctl "$device" dpi set 800 1 2>/dev/null
            ratbagctl "$device" dpi set 1600 2 2>/dev/null
            _notify "DPI profiles: 400 / 800 / 1600"
            ;;
        *Productivity*)
            ratbagctl "$device" dpi set 800 0 2>/dev/null
            ratbagctl "$device" dpi set 1200 1 2>/dev/null
            ratbagctl "$device" dpi set 2400 2 2>/dev/null
            _notify "DPI profiles: 800 / 1200 / 2400"
            ;;
        *"High-res"*)
            ratbagctl "$device" dpi set 1600 0 2>/dev/null
            ratbagctl "$device" dpi set 3200 1 2>/dev/null
            ratbagctl "$device" dpi set 6400 2 2>/dev/null
            _notify "DPI profiles: 1600 / 3200 / 6400"
            ;;
    esac
}

# ── Mouse Info (device, DPI, rate, buttons) ──

_mouse_info() {
    local info=""

    # Basic input devices
    local mice
    mice=$(grep -A4 "mouse\|Mouse" /proc/bus/input/devices 2>/dev/null | grep "N:" | sed 's/.*Name="//;s/"//')
    info+="Detected mice:\n"
    if [ -n "$mice" ]; then
        while IFS= read -r m; do
            info+="  • $m\n"
        done <<< "$mice"
    else
        info+="  (none detected)\n"
    fi

    # ratbagctl details
    if _ratbag_available; then
        local device
        device=$(_ratbag_device)
        if [ -n "$device" ]; then
            info+="\nConfigurable device: $device\n"
            local dpi rate
            dpi=$(ratbagctl "$device" dpi get 2>/dev/null | head -5)
            rate=$(ratbagctl "$device" rate get 2>/dev/null)
            [ -n "$dpi" ] && info+="\nDPI:\n$dpi\n"
            [ -n "$rate" ] && info+="\nPolling rate: $rate\n"
        fi
    else
        info+="\nInstall libratbag for DPI/rate control:\n  sudo pacman -S libratbag\n  sudo systemctl enable --now ratbagd\n"
    fi

    # Current software settings
    local sens accel
    sens=$(_input_get "sensitivity" "0")
    accel=$(_input_get "accel_profile" "adaptive")
    info+="\nSoftware settings:\n"
    info+="  Sensitivity: $sens\n"
    info+="  Accel profile: $accel\n"

    echo -e "$info" | _yad_pipe "  Mouse Info" >/dev/null
}

_menu_mouse_sub() {
    while true; do
        local choice
        choice=$(_yad_select "  Mouse" \
            "  Sensitivity" \
            "  Accel profile" \
            "  Natural scroll" \
            "  Scroll speed" \
            "  Left-handed mode" \
            "  Focus follows mouse" \
            "  DPI" \
            "  Polling rate" \
            "  DPI profiles" \
            "  Mouse info" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *Sensitivity*)      _mouse_sensitivity ;;
            *Accel*)            _mouse_accel_profile ;;
            *"Natural scroll"*) _mouse_natural_scroll ;;
            *"Scroll speed"*)   _mouse_scroll_factor ;;
            *Left*)             _mouse_left_handed ;;
            *Focus*)            _mouse_follow ;;
            *"DPI profiles"*)   _mouse_dpi_profiles ;;
            *DPI*)              _mouse_dpi ;;
            *"Polling rate"*)   _mouse_polling_rate ;;
            *"Mouse info"*)     _mouse_info ;;
        esac
    done
}

_menu_touchpad_sub() {
    while true; do
        local choice
        choice=$(_yad_select "  Touchpad" \
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
    choice=$(_yad_select "  Temperature (${current}K)" \
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
    choice=$(_yad_select "  Schedule ($mode)" \
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
            start=$(_yad_input "  Start hour (e.g. 20:00)")
            [ -z "$start" ] && return
            local end
            end=$(_yad_input "  End hour (e.g. 06:00)")
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
        choice=$(_yad_select "  Night Light ($status)" \
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

    choice=$(_yad_select "  Profile ($current)" \
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
    if command -v hyprctl &>/dev/null; then
        current=$(_hyprctl_get misc:dpms_timeout int)
        [ -z "$current" ] || [ "$current" = "0" ] && current="off"
        [ "$current" != "off" ] && current="${current}s"
    else
        current="unknown"
    fi

    local choice
    choice=$(_yad_select "  Screen off after ($current)" \
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
        *" 5 minute"*)  seconds=300 ;;   # leading space: "15 minutes" contains "5 minute"
        *"10 minute"*)  seconds=600 ;;
        *"15 minute"*)  seconds=900 ;;
        *"30 minute"*)  seconds=1800 ;;
        *Never*)        seconds=0 ;;
    esac

    if command -v hyprctl &>/dev/null; then
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
    choice=$(_yad_select "  Auto Suspend" \
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

    _yad_select "  Battery Info" \
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
        choice=$(_yad_select "  Power Management" \
            "  Power profile ($profile)" \
            "  Fan & Performance" \
            "  Screen off timeout" \
            "  Auto suspend" \
            "  Battery info" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *"Power profile"*)     _power_set_profile ;;
            *"Fan & Performance"*) _menu_fan_perf ;;
            *"Screen off"*)        _power_idle_timeout ;;
            *"Auto suspend"*)      _power_auto_suspend ;;
            *Battery*)             _power_battery_info ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════
#   FAN & PERFORMANCE (NitroSense-like controls)
#   Supports: Div Acer Manager Max, acer-wmi kernel module,
#             NBFC, and generic sysfs/hwmon fan control
# ══════════════════════════════════════════════════════════════

# ── Detection: which fan control backend is available ──

_fan_backend() {
    # 1. Div Acer Manager Max (full Acer Nitro GUI tool)
    if command -v div-acer-manager &>/dev/null; then
        echo "div-acer"
        return
    fi

    # 2. acer-predator kernel module (acer_wmi / acer-predator-turbo)
    if [ -d /sys/module/acer_wmi ] || [ -f /sys/devices/platform/acer-wmi/fan_mode ]; then
        echo "acer-wmi"
        return
    fi

    # 3. Custom acer-predator-turbo kernel module
    if [ -f /sys/module/acer_predator_turbo/parameters/fan_mode ] || \
       [ -d /sys/devices/platform/acer-predator ]; then
        echo "acer-predator"
        return
    fi

    # 4. NBFC (Notebook Fan Control)
    if command -v nbfc &>/dev/null || command -v nbfc_service &>/dev/null; then
        echo "nbfc"
        return
    fi

    # 5. Generic hwmon (PWM fans via sysfs)
    if ls /sys/class/hwmon/hwmon*/pwm1 &>/dev/null 2>&1; then
        echo "hwmon"
        return
    fi

    echo "none"
}

# ── Read current fan speeds ──

_fan_read_speeds() {
    local info=""
    local found=false

    # Read from hwmon fan RPM sensors
    for hwmon in /sys/class/hwmon/hwmon*; do
        local name=""
        [ -f "$hwmon/name" ] && name=$(cat "$hwmon/name" 2>/dev/null)
        for fan_input in "$hwmon"/fan*_input; do
            [ -f "$fan_input" ] || continue
            local rpm label fan_num
            rpm=$(cat "$fan_input" 2>/dev/null)
            fan_num=$(echo "$fan_input" | grep -oP 'fan\K\d+')
            [ -f "${hwmon}/fan${fan_num}_label" ] && \
                label=$(cat "${hwmon}/fan${fan_num}_label" 2>/dev/null) || \
                label="Fan $fan_num"
            [ -n "$name" ] && label="$label ($name)"
            info+="  $label: ${rpm} RPM\n"
            found=true
        done
    done

    # ACPI thermal fans
    if [ "$found" = false ]; then
        for zone in /sys/class/thermal/cooling_device*; do
            [ -f "$zone/type" ] || continue
            local type cur max
            type=$(cat "$zone/type" 2>/dev/null)
            [[ "$type" == *fan* ]] || [[ "$type" == *Fan* ]] || continue
            cur=$(cat "$zone/cur_state" 2>/dev/null)
            max=$(cat "$zone/max_state" 2>/dev/null)
            info+="  $type: state $cur / $max\n"
            found=true
        done
    fi

    [ "$found" = false ] && info+="  (no fan sensors detected)\n"
    echo -e "$info"
}

# ── Read temperatures ──

_fan_read_temps() {
    local info=""

    # hwmon temperatures
    for hwmon in /sys/class/hwmon/hwmon*; do
        local name=""
        [ -f "$hwmon/name" ] && name=$(cat "$hwmon/name" 2>/dev/null)
        for temp_input in "$hwmon"/temp*_input; do
            [ -f "$temp_input" ] || continue
            local temp label temp_num
            temp=$(cat "$temp_input" 2>/dev/null)
            temp=$((temp / 1000))
            temp_num=$(echo "$temp_input" | grep -oP 'temp\K\d+')
            [ -f "${hwmon}/temp${temp_num}_label" ] && \
                label=$(cat "${hwmon}/temp${temp_num}_label" 2>/dev/null) || \
                label="Sensor $temp_num"
            [ -n "$name" ] && label="$label ($name)"
            info+="  $label: ${temp}°C\n"
        done
    done

    # Fallback: thermal zones
    if [ -z "$info" ]; then
        for zone in /sys/class/thermal/thermal_zone*; do
            [ -f "$zone/temp" ] || continue
            local temp type
            temp=$(cat "$zone/temp" 2>/dev/null)
            temp=$((temp / 1000))
            type=$(cat "$zone/type" 2>/dev/null)
            info+="  $type: ${temp}°C\n"
        done
    fi

    [ -z "$info" ] && info="  (no temperature sensors detected)\n"
    echo -e "$info"
}

# ── Fan & Performance: Status overview ──

_fan_status() {
    local backend
    backend=$(_fan_backend)

    local info="Fan Control Backend: $backend\n\n"
    info+="Fan Speeds:\n"
    info+=$(_fan_read_speeds)
    info+="\nTemperatures:\n"
    info+=$(_fan_read_temps)

    # CPU governor
    local gov=""
    if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
        gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)
        info+="\nCPU Governor: $gov\n"
    fi

    # Power profile
    if command -v powerprofilesctl &>/dev/null; then
        local profile
        profile=$(powerprofilesctl get 2>/dev/null)
        info+="Power Profile: $profile\n"
    fi

    # NBFC status
    if [ "$backend" = "nbfc" ]; then
        local nbfc_status
        nbfc_status=$(nbfc status 2>/dev/null || nbfc_service --status 2>/dev/null)
        [ -n "$nbfc_status" ] && info+="\nNBFC Status:\n$nbfc_status\n"
    fi

    echo -e "$info" | _yad_pipe "  Fan & Performance Status" >/dev/null
}

# ── Fan Mode (Acer WMI / Predator module) ──

_fan_mode_acer_wmi() {
    local mode_file=""
    [ -f /sys/devices/platform/acer-wmi/fan_mode ] && mode_file="/sys/devices/platform/acer-wmi/fan_mode"
    [ -f /sys/module/acer_predator_turbo/parameters/fan_mode ] && mode_file="/sys/module/acer_predator_turbo/parameters/fan_mode"

    if [ -z "$mode_file" ]; then
        _notify "Acer WMI fan mode file not found"
        return
    fi

    local current
    current=$(cat "$mode_file" 2>/dev/null)
    local current_label="unknown"
    case "$current" in
        0) current_label="Auto" ;;
        1) current_label="Turbo" ;;
        2) current_label="Silent" ;;
        *) current_label="$current" ;;
    esac

    local choice
    choice=$(_yad_select "  Fan Mode ($current_label)" \
        "  Auto (system-controlled)" \
        "  Turbo (max performance)" \
        "  Silent (quiet, reduced speed)" \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    local val
    case "$choice" in
        *Auto*)   val=0 ;;
        *Turbo*)  val=1 ;;
        *Silent*) val=2 ;;
    esac

    echo "$val" | sudo tee "$mode_file" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        _input_save "fan_mode" "$val"
        _notify "Fan mode: $(echo "$choice" | sed 's/^[[:space:]]*//')"
    else
        _notify "Failed to set fan mode (needs root)"
    fi
}

# ── Fan Speed: Manual PWM control (generic hwmon) ──

_fan_speed_manual() {
    # Find first controllable PWM fan
    local pwm_file=""
    local pwm_enable=""
    for hwmon in /sys/class/hwmon/hwmon*; do
        if [ -f "$hwmon/pwm1" ]; then
            pwm_file="$hwmon/pwm1"
            pwm_enable="$hwmon/pwm1_enable"
            break
        fi
    done

    if [ -z "$pwm_file" ]; then
        _notify "No PWM fan control found.\nYour hardware may not support manual fan speed."
        return
    fi

    local current
    current=$(cat "$pwm_file" 2>/dev/null)
    local pct=$((current * 100 / 255))

    local choice
    choice=$(_yad_select "  Fan Speed (${pct}%)" \
        "  Auto (system-controlled)" \
        "  30% (quiet)" \
        "  50% (balanced)" \
        "  70% (cooling)" \
        "  85% (aggressive)" \
        "  100% (max)" \
        "  Custom..." \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    if [[ "$choice" == *"Auto"* ]]; then
        # Enable automatic fan control
        echo "2" | sudo tee "$pwm_enable" >/dev/null 2>&1
        _input_save "fan_speed" "auto"
        _notify "Fan: auto mode"
        return
    fi

    local val_pct
    if [[ "$choice" == *"Custom"* ]]; then
        val_pct=$(_yad_input "  Fan speed % (20–100)")
        [ -z "$val_pct" ] && return
        if ! [[ "$val_pct" =~ ^[0-9]+$ ]] || [ "$val_pct" -lt 20 ] || [ "$val_pct" -gt 100 ]; then
            _notify "Invalid: $val_pct (must be 20–100)"
            return
        fi
    else
        val_pct=$(echo "$choice" | grep -oP '\d+')
    fi

    local pwm_val=$((val_pct * 255 / 100))

    # Switch to manual mode first, then set speed
    echo "1" | sudo tee "$pwm_enable" >/dev/null 2>&1
    echo "$pwm_val" | sudo tee "$pwm_file" >/dev/null 2>&1

    if [ $? -eq 0 ]; then
        _input_save "fan_speed" "$val_pct"
        _notify "Fan speed: ${val_pct}%"
    else
        _notify "Failed to set fan speed (needs root)"
    fi
}

# ── NBFC Fan Control ──

_fan_nbfc_set_speed() {
    local nbfc_cmd="nbfc"
    command -v nbfc_service &>/dev/null && nbfc_cmd="nbfc_service"

    local choice
    choice=$(_yad_select "  NBFC Fan Speed" \
        "  Auto (recommended)" \
        "  25% (quiet)" \
        "  50% (balanced)" \
        "  75% (performance)" \
        "  100% (max)" \
        "  Custom..." \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    if [[ "$choice" == *"Auto"* ]]; then
        sudo $nbfc_cmd set -a 2>/dev/null
        _notify "NBFC: auto fan speed"
        return
    fi

    local val
    if [[ "$choice" == *"Custom"* ]]; then
        val=$(_yad_input "  Fan speed % (0–100)")
        [ -z "$val" ] && return
    else
        val=$(echo "$choice" | grep -oP '\d+')
    fi

    sudo $nbfc_cmd set -s "$val" 2>/dev/null
    _notify "NBFC fan speed: ${val}%"
}

_fan_nbfc_config() {
    local nbfc_cmd="nbfc"
    command -v nbfc_service &>/dev/null && nbfc_cmd="nbfc_service"

    local configs
    configs=$(sudo $nbfc_cmd config -l 2>/dev/null | head -30)

    if [ -z "$configs" ]; then
        _notify "No NBFC configs found.\nCheck: sudo nbfc config -l"
        return
    fi

    local choice
    choice=$(echo "$configs" | _yad_pipe "  NBFC Config (select your laptop)")
    [ -z "$choice" ] && return

    sudo $nbfc_cmd config -s "$choice" 2>/dev/null
    sudo systemctl restart nbfc_service 2>/dev/null || \
        sudo systemctl restart nbfc 2>/dev/null
    _notify "NBFC config: $choice"
}

# ── Div Acer Manager (launch GUI) ──

_fan_div_acer_launch() {
    if command -v div-acer-manager &>/dev/null; then
        div-acer-manager &
        disown
        _notify "Div Acer Manager launched"
    else
        _notify "Div Acer Manager not installed.\n\nInstall from AUR:\nyay -S div-acer-manager-max-git\n\nGitHub:\ngithub.com/PXDiv/Div-Acer-Manager-Max"
    fi
}

_fan_div_acer_stoa_theme() {
    local script_dir
    script_dir="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
    local apply_script="${script_dir}/theme/div-acer-manager/stoa-damx-apply.sh"

    if [ ! -f "$apply_script" ]; then
        _notify "Theme script not found.\nRun install.sh first."
        return
    fi

    local choice
    choice=$(_yad_select "  DAMX Stoa Theme" \
        "  Apply Stoa theme" \
        "  Restore original theme" \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    case "$choice" in
        *Apply*)
            bash "$apply_script" apply 2>/dev/null
            _notify "Stoa theme applied to Div Acer Manager.\nRestart DAMX to see changes."
            ;;
        *Restore*)
            bash "$apply_script" restore 2>/dev/null
            _notify "Original theme restored.\nRestart DAMX to see changes."
            ;;
    esac
}

# ── Performance Profiles (CPU governor + power profile) ──

_fan_perf_profile() {
    local current_gov=""
    [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ] && \
        current_gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)

    local current_pp=""
    command -v powerprofilesctl &>/dev/null && \
        current_pp=$(powerprofilesctl get 2>/dev/null)

    local label="$current_gov"
    [ -n "$current_pp" ] && label="$current_pp / $current_gov"

    local choice
    choice=$(_yad_select "  Performance Profile ($label)" \
        "  Eco (power-saver + powersave)" \
        "  Silent (power-saver + powersave)" \
        "  Balanced (balanced + schedutil)" \
        "  Performance (performance + performance)" \
        "  Turbo (performance + performance + no thermal limit)" \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    local pp_profile gov fan_mode
    case "$choice" in
        *Eco*)
            pp_profile="power-saver"
            gov="powersave"
            fan_mode="silent"
            ;;
        *Silent*)
            pp_profile="power-saver"
            gov="powersave"
            fan_mode="silent"
            ;;
        *Balanced*)
            pp_profile="balanced"
            gov="schedutil"
            fan_mode="auto"
            ;;
        *Performance*)
            pp_profile="performance"
            gov="performance"
            fan_mode="auto"
            ;;
        *Turbo*)
            pp_profile="performance"
            gov="performance"
            fan_mode="turbo"
            ;;
    esac

    # Apply power profile
    if command -v powerprofilesctl &>/dev/null && [ -n "$pp_profile" ]; then
        powerprofilesctl set "$pp_profile" 2>/dev/null
    fi

    # Apply CPU governor
    if [ -n "$gov" ]; then
        for cpu_gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            [ -f "$cpu_gov" ] && echo "$gov" | sudo tee "$cpu_gov" >/dev/null 2>&1
        done
    fi

    # Apply fan mode (Acer WMI)
    local backend
    backend=$(_fan_backend)
    if [ "$backend" = "acer-wmi" ] || [ "$backend" = "acer-predator" ]; then
        local mode_file=""
        [ -f /sys/devices/platform/acer-wmi/fan_mode ] && mode_file="/sys/devices/platform/acer-wmi/fan_mode"
        [ -f /sys/module/acer_predator_turbo/parameters/fan_mode ] && mode_file="/sys/module/acer_predator_turbo/parameters/fan_mode"
        if [ -n "$mode_file" ]; then
            case "$fan_mode" in
                auto)   echo "0" | sudo tee "$mode_file" >/dev/null 2>&1 ;;
                turbo)  echo "1" | sudo tee "$mode_file" >/dev/null 2>&1 ;;
                silent) echo "2" | sudo tee "$mode_file" >/dev/null 2>&1 ;;
            esac
        fi
    fi

    _input_save "perf_profile" "$(echo "$choice" | awk '{print $2}')"
    _notify "Profile: $(echo "$choice" | sed 's/^[[:space:]]*//')"
}

# ── Keyboard Backlight Timeout (Acer) ──

_fan_kb_backlight_timeout() {
    local timeout_file=""
    [ -f /sys/devices/platform/acer-wmi/kb_backlight_timeout ] && \
        timeout_file="/sys/devices/platform/acer-wmi/kb_backlight_timeout"

    if [ -z "$timeout_file" ]; then
        _notify "Keyboard backlight timeout not supported.\n(Requires Acer WMI driver)"
        return
    fi

    local current
    current=$(cat "$timeout_file" 2>/dev/null)

    local choice
    choice=$(_yad_select "  KB Backlight Timeout (${current}s)" \
        "  0 (always on)" \
        "  15 seconds" \
        "  30 seconds" \
        "  60 seconds" \
        "  120 seconds" \
        "  300 seconds" \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    local val
    val=$(echo "$choice" | grep -oP '\d+')
    echo "$val" | sudo tee "$timeout_file" >/dev/null 2>&1
    _input_save "kb_backlight_timeout" "$val"
    _notify "KB backlight timeout: ${val}s"
}

# ── Boot Sound Toggle (Acer) ──

_fan_boot_sound() {
    local sound_file=""
    [ -f /sys/devices/platform/acer-wmi/boot_sound ] && \
        sound_file="/sys/devices/platform/acer-wmi/boot_sound"

    if [ -z "$sound_file" ]; then
        _notify "Boot sound control not supported.\n(Requires Acer WMI driver)"
        return
    fi

    local current label
    current=$(cat "$sound_file" 2>/dev/null)
    [ "$current" = "1" ] && label="on" || label="off"

    local choice
    choice=$(_yad_select "  Boot Sound ($label)" \
        "  Enable" \
        "  Disable" \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    local val
    [[ "$choice" == *"Enable"* ]] && val=1 || val=0
    echo "$val" | sudo tee "$sound_file" >/dev/null 2>&1
    [ "$val" = "1" ] && _notify "Boot sound: on" || _notify "Boot sound: off"
}

# ── LCD Override (Acer) ──

_fan_lcd_override() {
    local lcd_file=""
    [ -f /sys/devices/platform/acer-wmi/lcd_override ] && \
        lcd_file="/sys/devices/platform/acer-wmi/lcd_override"

    if [ -z "$lcd_file" ]; then
        _notify "LCD override not supported.\n(Requires Acer WMI driver)"
        return
    fi

    local current label
    current=$(cat "$lcd_file" 2>/dev/null)
    [ "$current" = "1" ] && label="on" || label="off"

    local choice
    choice=$(_yad_select "  LCD Override ($label)" \
        "  Enable" \
        "  Disable" \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    local val
    [[ "$choice" == *"Enable"* ]] && val=1 || val=0
    echo "$val" | sudo tee "$lcd_file" >/dev/null 2>&1
    [ "$val" = "1" ] && _notify "LCD override: on" || _notify "LCD override: off"
}

# ── GPU Mode (Acer — dedicated / hybrid) ──

_fan_gpu_mode() {
    local gpu_file=""
    [ -f /sys/devices/platform/acer-wmi/gpu_mode ] && \
        gpu_file="/sys/devices/platform/acer-wmi/gpu_mode"

    if [ -z "$gpu_file" ]; then
        _notify "GPU mode switching not supported.\n(Requires Acer WMI driver)"
        return
    fi

    local current label
    current=$(cat "$gpu_file" 2>/dev/null)
    case "$current" in
        0) label="Integrated" ;;
        1) label="Dedicated" ;;
        *) label="$current" ;;
    esac

    local choice
    choice=$(_yad_select "  GPU Mode ($label)" \
        "  Integrated (power-saving)" \
        "  Dedicated (performance)" \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    local val
    [[ "$choice" == *"Integrated"* ]] && val=0 || val=1
    echo "$val" | sudo tee "$gpu_file" >/dev/null 2>&1
    _notify "GPU mode: $(echo "$choice" | sed 's/^[[:space:]]*//')"
}

# ── Setup Help ──

_fan_setup_help() {
    local backend
    backend=$(_fan_backend)

    local info="Current backend: $backend\n\n"

    info+="Available tools for fan & performance control:\n\n"

    info+="1. Div Acer Manager Max (recommended for Acer laptops)\n"
    info+="   GUI tool with fan, profiles, RGB, LCD, boot sound.\n"
    info+="   Install: yay -S div-acer-manager-max-git\n"
    info+="   GitHub: github.com/PXDiv/Div-Acer-Manager-Max\n\n"

    info+="2. Acer Predator kernel module\n"
    info+="   Fan mode + RGB for Acer Nitro/Predator laptops.\n"
    info+="   Install: yay -S acer-predator-turbo-and-rgb-keyboard-linux-module-dkms\n"
    info+="   GitHub: github.com/JafarAkhondali/acer-predator-turbo-and-rgb-keyboard-linux-module\n\n"

    info+="3. NBFC — Notebook Fan Control\n"
    info+="   Generic fan control for many laptop models.\n"
    info+="   Install: yay -S nbfc-git\n"
    info+="   GitHub: github.com/erpalma/nbfc\n\n"

    info+="4. Generic hwmon (built-in)\n"
    info+="   Direct PWM fan control via sysfs.\n"
    info+="   No additional packages needed.\n"
    info+="   Requires: lm_sensors (sudo sensors-detect)\n\n"

    info+="After installing, restart this panel to detect the backend.\n"

    echo -e "$info" | _yad_pipe "  Setup Help" >/dev/null
}

# ── Main Fan & Performance menu ──

_menu_fan_perf() {
    local backend
    backend=$(_fan_backend)

    while true; do
        # Build menu dynamically based on backend
        local items=()
        items+=("  Status & sensors")
        items+=("  Performance profiles")

        case "$backend" in
            div-acer)
                items+=("  Div Acer Manager (launch)")
                items+=("  Div Acer Manager (Stoa theme)")
                items+=("  Fan mode (Acer)")
                items+=("  Fan speed (manual)")
                items+=("  GPU mode")
                items+=("  KB backlight timeout")
                items+=("  Boot sound")
                items+=("  LCD override")
                ;;
            acer-wmi|acer-predator)
                items+=("  Fan mode (Acer)")
                items+=("  Fan speed (manual)")
                items+=("  GPU mode")
                items+=("  KB backlight timeout")
                items+=("  Boot sound")
                items+=("  LCD override")
                ;;
            nbfc)
                items+=("  Fan speed (NBFC)")
                items+=("  NBFC config (select laptop)")
                ;;
            hwmon)
                items+=("  Fan speed (manual)")
                ;;
            none)
                items+=("  Fan speed (manual)")
                ;;
        esac

        items+=("  Setup help & install")
        items+=("  Back")

        local choice
        choice=$(printf '%s\n' "${items[@]}" | _yad_pipe "  Fan & Performance ($backend)")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *"Status"*)             _fan_status ;;
            *"Performance profile"*) _fan_perf_profile ;;
            *"Div Acer Manager (Stoa"*) _fan_div_acer_stoa_theme ;;
            *"Div Acer"*)           _fan_div_acer_launch ;;
            *"Fan mode"*)           _fan_mode_acer_wmi ;;
            *"Fan speed (NBFC)"*)   _fan_nbfc_set_speed ;;
            *"Fan speed"*)          _fan_speed_manual ;;
            *"NBFC config"*)        _fan_nbfc_config ;;
            *"GPU mode"*)           _fan_gpu_mode ;;
            *"KB backlight"*)       _fan_kb_backlight_timeout ;;
            *"Boot sound"*)         _fan_boot_sound ;;
            *"LCD override"*)       _fan_lcd_override ;;
            *"Setup help"*)         _fan_setup_help ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════
#   KEYBOARD (layout, repeat, Caps Lock behavior)
# ══════════════════════════════════════════════════════════════

_kb_current_layout() {
    if command -v hyprctl &>/dev/null; then
        _hyprctl_get input:kb_layout str
    else
        setxkbmap -query 2>/dev/null | grep layout | awk '{print $2}'
    fi
}

_kb_layout() {
    local current
    current=$(_kb_current_layout)

    local choice
    choice=$(_yad_select "  Layout ($current)" \
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
        layout=$(_yad_input "  Layout code (e.g. latam)")
        [ -z "$layout" ] && return
    else
        layout=$(echo "$choice" | grep -oP '^\s*\S+\s+\K\S+' | tr -d '()')
        # Extract the code before the parenthesis
        layout=$(echo "$choice" | awk '{print $2}')
    fi

    if command -v hyprctl &>/dev/null; then
        hyprctl keyword input:kb_layout "$layout" &>/dev/null
        _notify "Keyboard layout: $layout"
    else
        setxkbmap "$layout" 2>/dev/null
        _notify "Keyboard layout: $layout"
    fi
}

_kb_repeat_rate() {
    local current_rate current_delay
    if command -v hyprctl &>/dev/null; then
        current_rate=$(_hyprctl_get input:repeat_rate int)
        current_delay=$(_hyprctl_get input:repeat_delay int)
    else
        current_rate="?"
        current_delay="?"
    fi

    local choice
    choice=$(_yad_select "  Repeat (rate:${current_rate} delay:${current_delay}ms)" \
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

    if command -v hyprctl &>/dev/null; then
        hyprctl keyword input:repeat_rate "$rate" &>/dev/null
        hyprctl keyword input:repeat_delay "$delay" &>/dev/null
    else
        xset r rate "$delay" "$rate" 2>/dev/null
    fi
    _notify "Repeat: rate $rate, delay ${delay}ms"
}

_kb_capslock_behavior() {
    local choice
    choice=$(_yad_select "  Caps Lock behavior" \
        "  Default (Caps Lock)" \
        "  Escape (vim-friendly)" \
        "  Ctrl (Emacs-friendly)" \
        "  Backspace" \
        "  Disabled" \
        "  Back")
    # Anchored: an unanchored *"Back"* also swallows "  Backspace".
    [ -z "$choice" ] || [[ "$choice" == *Back ]] && return

    local opt
    case "$choice" in
        *Default*)    opt="" ;;
        *Escape*)     opt="caps:escape" ;;
        *Ctrl*)       opt="ctrl:nocaps" ;;
        *Backspace*)  opt="caps:backspace" ;;
        *Disabled*)   opt="caps:none" ;;
    esac

    if command -v hyprctl &>/dev/null; then
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
    choice=$(_yad_select "  NumLock on boot" \
        "  On" \
        "  Off" \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    case "$choice" in
        *On*)
            if command -v hyprctl &>/dev/null; then
                hyprctl keyword input:numlock_by_default true &>/dev/null
            else
                numlockx on 2>/dev/null
            fi
            _notify "NumLock on boot: on"
            ;;
        *Off*)
            if command -v hyprctl &>/dev/null; then
                hyprctl keyword input:numlock_by_default false &>/dev/null
            else
                numlockx off 2>/dev/null
            fi
            _notify "NumLock on boot: off"
            ;;
    esac
}

# ── RGB Keyboard Control (via OpenRGB) ──

_rgb_available() {
    command -v openrgb &>/dev/null
}

_rgb_device_count() {
    openrgb --list-devices 2>/dev/null | grep -c "^[0-9]\+:"
}

_rgb_list_devices() {
    openrgb --list-devices 2>/dev/null | grep "^[0-9]\+:" | sed 's/^/  /'
}

_rgb_set_color() {
    local color="$1"
    # Apply to all devices
    openrgb --color "$color" 2>/dev/null
    _input_save "rgb_color" "$color"
    _notify "RGB color: #$color"
}

_rgb_set_mode() {
    local mode="$1"
    openrgb --mode "$mode" 2>/dev/null
    _input_save "rgb_mode" "$mode"
    _notify "RGB mode: $mode"
}

_kb_rgb_color() {
    if ! _rgb_available; then
        _notify "OpenRGB not installed.\nsudo pacman -S openrgb"
        return
    fi

    # Stoa palette colors + common RGB options
    local choice
    choice=$(_yad_select "  RGB Color" \
        "  Bronze (Stoa)       #c49a5c" \
        "  Gold (Stoa)         #d4a84b" \
        "  Olive (Stoa)        #8a9a6c" \
        "  Terracotta (Stoa)   #b36b5a" \
        "  Azure (Stoa)        #5a7a8a" \
        "  Marble (Stoa)       #d4cfc4" \
        "  White               #ffffff" \
        "  Red                 #ff0000" \
        "  Green               #00ff00" \
        "  Blue                #0000ff" \
        "  Cyan                #00ffff" \
        "  Purple              #8000ff" \
        "  Orange              #ff8000" \
        "  Pink                #ff0080" \
        "  Yellow              #ffff00" \
        "  Off                 #000000" \
        "  Custom..." \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    local color
    if [[ "$choice" == *"Custom"* ]]; then
        color=$(_yad_input "  Hex color (e.g. ff6600)")
        [ -z "$color" ] && return
        # Strip # if provided
        color="${color#\#}"
    else
        color=$(echo "$choice" | grep -oP '#\K[0-9a-fA-F]+')
    fi

    [ -z "$color" ] && return
    _rgb_set_color "$color"
}

_kb_rgb_mode() {
    if ! _rgb_available; then
        _notify "OpenRGB not installed.\nsudo pacman -S openrgb"
        return
    fi

    # Get available modes from OpenRGB
    local modes
    modes=$(openrgb --list-devices 2>/dev/null | grep -i "mode:" | sed 's/.*mode: //;s/^/  /' | sort -u)

    if [ -z "$modes" ]; then
        # Fallback to common modes
        modes="  Static
  Breathing
  Color Cycle
  Rainbow
  Wave
  Reactive
  Spectrum Cycle
  Off"
    fi

    local current
    current=$(_input_get "rgb_mode" "Static")

    local choice
    choice=$(_yad_select "  RGB Mode ($current)" \
        "  Static" \
        "  Breathing" \
        "  Color Cycle" \
        "  Spectrum Cycle" \
        "  Rainbow" \
        "  Wave" \
        "  Off" \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    local mode
    mode=$(echo "$choice" | sed 's/^[[:space:]]*//')
    _rgb_set_mode "$mode"
}

_kb_rgb_brightness() {
    if ! _rgb_available; then
        _notify "OpenRGB not installed.\nsudo pacman -S openrgb"
        return
    fi

    local choice
    choice=$(_yad_select "  RGB Brightness" \
        "  100% (full)" \
        "  75%" \
        "  50%" \
        "  25%" \
        "  10% (dim)" \
        "  0% (off)" \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    local val
    val=$(echo "$choice" | grep -oP '\d+')
    # Map 0-100 to 0-255
    local brightness=$(( val * 255 / 100 ))
    openrgb --brightness "$brightness" 2>/dev/null
    _input_save "rgb_brightness" "$val"
    _notify "RGB brightness: ${val}%"
}

_kb_rgb_off() {
    if ! _rgb_available; then
        _notify "OpenRGB not installed.\nsudo pacman -S openrgb"
        return
    fi
    openrgb --mode Static --color 000000 2>/dev/null
    _input_save "rgb_color" "000000"
    _input_save "rgb_mode" "Off"
    _notify "RGB: off"
}

_kb_rgb_stoa_theme() {
    if ! _rgb_available; then
        _notify "OpenRGB not installed.\nsudo pacman -S openrgb"
        return
    fi

    # Source current palette
    local color_file="${HOME}/.config/stoa/colors.sh"
    [ ! -f "$color_file" ] && color_file="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)/theme/colors.sh"

    if [ -f "$color_file" ]; then
        source "$color_file"
        local hex="${STOA_BRONZE#\#}"
        openrgb --mode Static --color "$hex" 2>/dev/null
        _input_save "rgb_color" "$hex"
        _input_save "rgb_mode" "Static"
        _notify "RGB: Stoa theme (bronze)"
    else
        # Fallback
        openrgb --mode Static --color "c49a5c" 2>/dev/null
        _notify "RGB: Stoa theme (bronze)"
    fi
}

_kb_rgb_info() {
    if ! _rgb_available; then
        local info="OpenRGB not installed.\n\nInstall:\n  sudo pacman -S openrgb\n\nStart the background service:\n  sudo systemctl enable --now openrgb\n\nSupported devices:\n  Most RGB keyboards, mice, RAM, GPUs, motherboards,\n  LED strips, and peripherals from Corsair, Razer,\n  Logitech, SteelSeries, ASUS, MSI, etc."
        echo -e "$info" | _yad_pipe "  RGB Info" >/dev/null
        return
    fi

    local info=""
    info+="OpenRGB devices:\n"
    local devices
    devices=$(openrgb --list-devices 2>/dev/null)
    if [ -n "$devices" ]; then
        info+="$devices\n"
    else
        info+="  (no devices detected — is openrgb running?)\n"
        info+="\n  Start: openrgb --server &\n"
    fi

    local saved_color saved_mode
    saved_color=$(_input_get "rgb_color" "(not set)")
    saved_mode=$(_input_get "rgb_mode" "(not set)")
    info+="\nSaved settings:\n"
    info+="  Color: #$saved_color\n"
    info+="  Mode: $saved_mode\n"

    echo -e "$info" | _yad_pipe "  RGB Info" >/dev/null
}

_menu_rgb() {
    while true; do
        local choice
        choice=$(_yad_select "  RGB Control" \
            "  Color" \
            "  Mode (effect)" \
            "  Brightness" \
            "  Stoa theme" \
            "  Turn off" \
            "  Device info" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *Color*)       _kb_rgb_color ;;
            *Mode*)        _kb_rgb_mode ;;
            *Brightness*)  _kb_rgb_brightness ;;
            *"Stoa theme"*) _kb_rgb_stoa_theme ;;
            *"Turn off"*)  _kb_rgb_off ;;
            *"Device info"*) _kb_rgb_info ;;
        esac
    done
}

menu_keyboard() {
    while true; do
        local layout
        layout=$(_kb_current_layout)

        local choice
        choice=$(_yad_select "  Keyboard" \
            "  Layout ($layout)" \
            "  Repeat rate & delay" \
            "  Caps Lock behavior" \
            "  NumLock on boot" \
            "  RGB lighting" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *Layout*)     _kb_layout ;;
            *Repeat*)     _kb_repeat_rate ;;
            *Caps*)       _kb_capslock_behavior ;;
            *NumLock*)    _kb_numlock ;;
            *RGB*)        _menu_rgb ;;
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
    choice=$(_yad_select "  Printers" "${items[@]}" "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    local selected
    selected=$(echo "$choice" | awk '{print $2}')

    local action
    action=$(_yad_select "  $selected" \
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
            _yad_confirm "Remove $selected?" && {
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
        _yad_confirm "Stop CUPS service?" && {
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
    choice=$(echo "$jobs" | _yad_pipe "  Print queue")
    [ -z "$choice" ] && return

    local job_id
    job_id=$(echo "$choice" | awk '{print $1}')

    _yad_confirm "Cancel job $job_id?" && {
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

    echo "$scanners" | _yad_pipe "  Scanners" >/dev/null
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
        choice=$(_yad_select "  Printers & Scanners" \
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
    choice=$(_yad_select "  Timezone ($current)" \
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
        query=$(_yad_input "  Search timezone (e.g. Tokyo)")
        [ -z "$query" ] && return
        tz=$(timedatectl list-timezones 2>/dev/null | grep -i "$query" | _yad_pipe "  Results")
        [ -z "$tz" ] && return
    else
        tz=$(echo "$choice" | sed 's/^[[:space:]]*//' | sed 's/^[^ ]* //')
    fi

    _yad_confirm "Set timezone to $tz?" && {
        sudo timedatectl set-timezone "$tz" 2>/dev/null
        _notify "Timezone: $tz"
    }
}

_dt_toggle_ntp() {
    local ntp_status
    ntp_status=$(timedatectl show --property=NTP --value 2>/dev/null)

    if [ "$ntp_status" = "yes" ]; then
        _yad_confirm "Disable auto time sync (NTP)?" && {
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
    date_input=$(_yad_input "  Date (YYYY-MM-DD)")
    [ -z "$date_input" ] && return

    local time_input
    time_input=$(_yad_input "  Time (HH:MM:SS)")
    [ -z "$time_input" ] && return

    _yad_confirm "Set to ${date_input} ${time_input}?" && {
        sudo timedatectl set-time "${date_input} ${time_input}" 2>/dev/null
        _notify "Time set: ${date_input} ${time_input}"
    }
}

_dt_24h_toggle() {
    local current
    current=$(gsettings get org.gnome.desktop.interface clock-format 2>/dev/null || echo "'24h'")

    local choice
    choice=$(_yad_select "  Clock format" \
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
    choice=$(_yad_select "  Language ($current)" \
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

    _yad_confirm "Set language to ${locale_val}? (requires logout)" && {
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
        choice=$(_yad_select "  Date & Time ($now)" \
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
#   ACCESSIBILITY
# ══════════════════════════════════════════════════════════════

_a11y_cursor_size() {
    local current
    current=$(gsettings get org.gnome.desktop.interface cursor-size 2>/dev/null || echo "24")

    local choice
    choice=$(_yad_select "  Cursor size (${current}px)" \
        "  24 (default)" \
        "  32 (large)" \
        "  48 (extra large)" \
        "  64 (huge)" \
        "  96 (maximum)" \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    local size
    size=$(echo "$choice" | grep -oP '\d+' | head -1)

    gsettings set org.gnome.desktop.interface cursor-size "$size" 2>/dev/null
    if command -v hyprctl &>/dev/null; then
        hyprctl keyword env "XCURSOR_SIZE,$size" &>/dev/null
    fi
    _notify "Cursor size: ${size}px"
}

_a11y_text_scaling() {
    local current
    current=$(gsettings get org.gnome.desktop.interface text-scaling-factor 2>/dev/null || echo "1.0")

    local choice
    choice=$(_yad_select "  Text scale (${current}x)" \
        "  1.0 (default)" \
        "  1.25 (125%)" \
        "  1.5 (150%)" \
        "  1.75 (175%)" \
        "  2.0 (200%)" \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    local factor
    factor=$(echo "$choice" | grep -oP '\d+\.\d+' | head -1)

    gsettings set org.gnome.desktop.interface text-scaling-factor "$factor" 2>/dev/null
    _notify "Text scale: ${factor}x"
}

_a11y_animations() {
    local current="on"
    if command -v hyprctl &>/dev/null; then
        local enabled
        enabled=$(_hyprctl_get animations:enabled int)
        [ "$enabled" = "0" ] && current="off"
    fi

    local choice
    choice=$(_yad_select "  Animations ($current)" \
        "  Enable animations" \
        "  Disable animations" \
        "  Reduce motion (slower)" \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    if command -v hyprctl &>/dev/null; then
        case "$choice" in
            *Enable*)
                hyprctl keyword animations:enabled true &>/dev/null
                _notify "Animations: enabled"
                ;;
            *Disable*)
                hyprctl keyword animations:enabled false &>/dev/null
                gsettings set org.gnome.desktop.interface enable-animations false 2>/dev/null
                _notify "Animations: disabled"
                ;;
            *Reduce*)
                hyprctl keyword animations:enabled true &>/dev/null
                hyprctl keyword animation "windows, 1, 8, default" &>/dev/null
                hyprctl keyword animation "fade, 1, 8, default" &>/dev/null
                hyprctl keyword animation "workspaces, 1, 6, default" &>/dev/null
                _notify "Animations: reduced motion"
                ;;
        esac
    else
        case "$choice" in
            *Enable*)
                gsettings set org.gnome.desktop.interface enable-animations true 2>/dev/null
                _notify "Animations: enabled"
                ;;
            *Disable*)
                gsettings set org.gnome.desktop.interface enable-animations false 2>/dev/null
                _notify "Animations: disabled"
                ;;
        esac
    fi
}

_a11y_gaps() {
    if ! command -v hyprctl &>/dev/null; then
        _notify "Gaps only available on Hyprland"
        return
    fi

    local current_in current_out
    current_in=$(_hyprctl_get general:gaps_in custom)
    current_out=$(_hyprctl_get general:gaps_out custom)

    local choice
    choice=$(_yad_select "  Gaps (in:${current_in} out:${current_out})" \
        "  None (0/0)" \
        "  Minimal (1/2)" \
        "  Default (3/6)" \
        "  Comfortable (5/10)" \
        "  Spacious (8/16)" \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    local gin gout
    case "$choice" in
        *None*)        gin=0; gout=0 ;;
        *Minimal*)     gin=1; gout=2 ;;
        *Default*)     gin=3; gout=6 ;;
        *Comfortable*) gin=5; gout=10 ;;
        *Spacious*)    gin=8; gout=16 ;;
    esac

    hyprctl keyword general:gaps_in "$gin" &>/dev/null
    hyprctl keyword general:gaps_out "$gout" &>/dev/null
    _notify "Gaps: in=$gin out=$gout"
}

_a11y_opacity() {
    if ! command -v hyprctl &>/dev/null; then
        _notify "Opacity only available on Hyprland"
        return
    fi

    local current
    current=$(_hyprctl_get decoration:inactive_opacity float)

    local choice
    choice=$(_yad_select "  Inactive window opacity (${current})" \
        "  100% (opaque)" \
        "  95%" \
        "  90% (default)" \
        "  85%" \
        "  80%" \
        "  70%" \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    local val
    case "$choice" in
        *100*) val="1.0" ;;
        *95*)  val="0.95" ;;
        *90*)  val="0.90" ;;
        *85*)  val="0.85" ;;
        *80*)  val="0.80" ;;
        *70*)  val="0.70" ;;
    esac

    hyprctl keyword decoration:inactive_opacity "$val" &>/dev/null
    _notify "Inactive opacity: $val"
}

_a11y_border_size() {
    if ! command -v hyprctl &>/dev/null; then
        _notify "Border size only available on Hyprland"
        return
    fi

    local current
    current=$(_hyprctl_get general:border_size int)

    local choice
    choice=$(_yad_select "  Border width (${current}px)" \
        "  0 (none)" \
        "  1 (thin)" \
        "  2 (default)" \
        "  3 (thick)" \
        "  4 (extra thick)" \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    local size
    size=$(echo "$choice" | grep -oP '^\s*\S+\s+\K\d+')

    hyprctl keyword general:border_size "$size" &>/dev/null
    _notify "Border width: ${size}px"
}

menu_accessibility() {
    while true; do
        local choice
        choice=$(_yad_select "  Accessibility" \
            "  Cursor size" \
            "  Text scaling" \
            "  Animations" \
            "  Window gaps" \
            "  Inactive opacity" \
            "  Border width" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *Cursor*)    _a11y_cursor_size ;;
            *Text*)      _a11y_text_scaling ;;
            *Animation*) _a11y_animations ;;
            *gaps*)      _a11y_gaps ;;
            *opacity*)   _a11y_opacity ;;
            *Border*)    _a11y_border_size ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════
#   AUDIO EQUALIZER (EasyEffects — PipeWire)
# ══════════════════════════════════════════════════════════════

EQ_PRESETS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/easyeffects/output"

_eq_running() {
    pgrep -x easyeffects &>/dev/null && echo "on" || echo "off"
}

_eq_toggle() {
    if pgrep -x easyeffects &>/dev/null; then
        easyeffects -q 2>/dev/null
        _notify "Equalizer: off"
    else
        easyeffects --gapplication-service &>/dev/null &
        disown
        _notify "Equalizer: on"
    fi
}

_eq_open_gui() {
    if ! pgrep -x easyeffects &>/dev/null; then
        easyeffects --gapplication-service &>/dev/null &
        disown
        sleep 1
    fi
    easyeffects &>/dev/null &
    disown
    _notify "Opening EasyEffects..."
}

_eq_presets() {
    # List available presets from EasyEffects config
    local presets=()

    # Built-in style presets (common EQ curves)
    presets+=("  Flat (default)")
    presets+=("  Bass Boost")
    presets+=("  Treble Boost")
    presets+=("  Vocal Clarity")
    presets+=("  Rock")
    presets+=("  Electronic")
    presets+=("  Classical")
    presets+=("  Podcast / Speech")

    # User presets from EasyEffects
    if [ -d "$EQ_PRESETS_DIR" ]; then
        local user_presets
        user_presets=$(find "$EQ_PRESETS_DIR" -name "*.json" -printf "%f\n" 2>/dev/null | sed 's/\.json$//')
        while IFS= read -r p; do
            [ -n "$p" ] && presets+=("  $p (saved)")
        done <<< "$user_presets"
    fi

    presets+=("  Back")

    local choice
    choice=$(_yad_select "  EQ Preset" "${presets[@]}")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    # Ensure EasyEffects is running
    if ! pgrep -x easyeffects &>/dev/null; then
        easyeffects --gapplication-service &>/dev/null &
        disown
        sleep 1
    fi

    local preset_name
    preset_name=$(echo "$choice" | sed 's/^[[:space:]]*//' | sed 's/^[^ ]* //' | sed 's/ (saved)$//')

    # For built-in presets, create the EQ config
    case "$choice" in
        *"Flat"*)
            _eq_apply_builtin "Flat" "0:0:0:0:0:0:0:0:0:0"
            ;;
        *"Bass Boost"*)
            _eq_apply_builtin "Bass Boost" "6:5:4:2:0:0:0:0:0:0"
            ;;
        *"Treble Boost"*)
            _eq_apply_builtin "Treble Boost" "0:0:0:0:0:2:3:4:5:6"
            ;;
        *"Vocal Clarity"*)
            _eq_apply_builtin "Vocal Clarity" "-2:0:2:4:4:3:2:0:-1:-2"
            ;;
        *"Rock"*)
            _eq_apply_builtin "Rock" "4:3:1:0:-1:-1:0:2:3:4"
            ;;
        *"Electronic"*)
            _eq_apply_builtin "Electronic" "5:4:2:0:-2:-1:0:2:4:5"
            ;;
        *"Classical"*)
            _eq_apply_builtin "Classical" "3:2:1:0:0:0:0:1:2:3"
            ;;
        *"Podcast"*|*"Speech"*)
            _eq_apply_builtin "Podcast" "-3:-1:2:4:4:3:1:0:-2:-3"
            ;;
        *"(saved)"*)
            local name
            name=$(echo "$choice" | sed 's/^[[:space:]]*//' | sed 's/^[^ ]* //' | sed 's/ (saved)$//')
            easyeffects -l "$name" 2>/dev/null
            _notify "Preset: $name"
            ;;
    esac
}

_eq_apply_builtin() {
    local name="$1"
    local gains="$2"

    # Create a simple preset JSON for EasyEffects
    mkdir -p "$EQ_PRESETS_DIR"
    local freqs=(31 63 125 250 500 1000 2000 4000 8000 16000)
    IFS=':' read -ra gain_arr <<< "$gains"

    local bands=""
    for i in "${!freqs[@]}"; do
        local g="${gain_arr[$i]:-0}"
        [ -n "$bands" ] && bands+=","
        bands+=$(printf '{"frequency":%d,"gain":%s,"mode":"RLC (BT)","q":1.5,"slope":"x1","type":"Bell"}' "${freqs[$i]}" "$g")
    done

    cat > "${EQ_PRESETS_DIR}/stoa-${name,,}.json" <<EQEOF
{
  "output": {
    "equalizer#0": {
      "bypass": false,
      "input-gain": 0.0,
      "num-bands": 10,
      "output-gain": 0.0,
      "split-channels": false,
      "left": [${bands}],
      "right": [${bands}]
    },
    "plugins_order": ["equalizer#0"]
  }
}
EQEOF

    easyeffects -l "stoa-${name,,}" 2>/dev/null
    _notify "Preset: $name"
}

menu_equalizer() {
    if ! command -v easyeffects &>/dev/null; then
        _notify "easyeffects not installed (pacman -S easyeffects)"
        return
    fi

    while true; do
        local status
        status=$(_eq_running)

        local choice
        choice=$(_yad_select "  Equalizer ($status)" \
            "  Toggle equalizer ($status)" \
            "  Presets" \
            "  Open EasyEffects" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *Toggle*)   _eq_toggle ;;
            *Presets*)  _eq_presets ;;
            *Open*)     _eq_open_gui ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════
#   SCREENSAVER (living marble animation)
# ══════════════════════════════════════════════════════════════

_ss_is_enabled() {
    local conf="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/screensaver.conf"
    [ -f "$conf" ] && grep -q "^ENABLED=true" "$conf" 2>/dev/null && echo "on" || echo "off"
}

_ss_current_timeout() {
    local conf="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/screensaver.conf"
    local val="300"
    [ -f "$conf" ] && {
        local v
        v=$(grep "^IDLE_TIMEOUT=" "$conf" 2>/dev/null | cut -d= -f2)
        [ -n "$v" ] && val="$v"
    }
    echo "$((val / 60))"
}

_ss_toggle() {
    local status
    status=$(_ss_is_enabled)
    if [ "$status" = "on" ]; then
        stoa-screensaver disable 2>/dev/null
        _notify "Screensaver: disabled"
    else
        stoa-screensaver enable 2>/dev/null
        _notify "Screensaver: enabled"
    fi
}

_ss_set_timeout() {
    local current
    current=$(_ss_current_timeout)

    local choice
    choice=$(_yad_select "  Idle timeout (${current} min)" \
        "  1 minute" \
        "  2 minutes" \
        "  5 minutes" \
        "  10 minutes" \
        "  15 minutes" \
        "  30 minutes" \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    local seconds
    case "$choice" in
        *"1 minute"*)   seconds=60 ;;
        *"2 minute"*)   seconds=120 ;;
        *" 5 minute"*)  seconds=300 ;;   # leading space: "15 minutes" contains "5 minute"
        *"10 minute"*)  seconds=600 ;;
        *"15 minute"*)  seconds=900 ;;
        *"30 minute"*)  seconds=1800 ;;
    esac

    stoa-screensaver set-timeout "$seconds" 2>/dev/null
    _notify "Screensaver timeout: $((seconds / 60)) min"
}

_ss_regenerate() {
    _notify "Generating screensaver animation..."
    kitty -e stoa-screensaver generate &
    disown
}

_ss_preview() {
    local video="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/screensaver/marble-flow.mp4"
    if [ ! -f "$video" ]; then
        _notify "No animation yet — generate first"
        return
    fi
    stoa-screensaver start &
    disown
}

menu_screensaver() {
    if ! command -v magick &>/dev/null; then
        _notify "imagemagick not installed"
        return
    fi

    while true; do
        local status
        status=$(_ss_is_enabled)
        local timeout
        timeout=$(_ss_current_timeout)

        local choice
        choice=$(_yad_select "  Screensaver ($status)" \
            "  Toggle ($status)" \
            "  Idle timeout (${timeout} min)" \
            "  Generate animation" \
            "  Preview" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *Toggle*)    _ss_toggle ;;
            *timeout*)   _ss_set_timeout ;;
            *Generate*)  _ss_regenerate ;;
            *Preview*)   _ss_preview ;;
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
        choice=$(_yad_select "  Stoa Config" \
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

# Session actions (lock/logout/reboot/shutdown) used to live in a "Power"
# menu here — removed as redundant with Noctalia's native control center
# session shortcut (control_center.shortcuts type="session" in
# config/noctalia/config.toml), which already covers all four.

# ══════════════════════════════════════════════════════════════
#   DISKS & STORAGE (gnome-disks + disk-usage-analyzer)
# ══════════════════════════════════════════════════════════════

# ── Overview: all disks with partitions ──
_disk_overview() {
    local lines=()
    lines+=("─── Physical Disks ───")

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local name size model serial transport
        name=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $2}')
        model=$(echo "$line" | awk '{$1=$2=""; print $0}' | xargs)
        lines+=("  /dev/$name  $size  ${model:-unknown}")
    done < <(lsblk -dno NAME,SIZE,MODEL 2>/dev/null | grep -E '^(sd|nvme|vd|mmcblk)')

    lines+=("")
    lines+=("─── Partitions ───")

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local name size fstype label mount
        name=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $2}')
        fstype=$(echo "$line" | awk '{print $3}')
        label=$(echo "$line" | awk '{print $4}')
        mount=$(echo "$line" | awk '{print $5}')
        [ -z "$fstype" ] && continue
        local desc="/dev/$name  $size  $fstype"
        [ -n "$label" ] && desc+="  [$label]"
        [ -n "$mount" ] && desc+="  → $mount" || desc+="  (not mounted)"
        lines+=("  $desc")
    done < <(lsblk -lno NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT 2>/dev/null | grep -vE '^(loop|sr)')

    lines+=("")
    lines+=("─── Usage ───")
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
        [[ "$fs" == overlay ]] && continue
        lines+=("  $mount  $used/$size  $pct used  ($avail free)")
    done < <(df -h 2>/dev/null | tail -n +2)

    printf '%s\n' "${lines[@]}"
}

# ── Disk health (SMART) ──
_disk_smart() {
    if ! command -v smartctl &>/dev/null; then
        _notify "smartmontools not installed (pacman -S smartmontools)"
        return
    fi

    local disks=()
    while IFS= read -r d; do
        [ -n "$d" ] && disks+=("/dev/$d")
    done < <(lsblk -dno NAME 2>/dev/null | grep -E '^(sd|nvme|vd)')

    [ ${#disks[@]} -eq 0 ] && { _notify "No disks found"; return; }

    local disk
    if [ ${#disks[@]} -eq 1 ]; then
        disk="${disks[0]}"
    else
        disk=$(printf '%s\n' "${disks[@]}" | _yad_pipe "  Select disk")
        [ -z "$disk" ] && return
    fi

    local lines=()
    lines+=("─── SMART Health: $disk ───")

    local health
    health=$(sudo smartctl -H "$disk" 2>/dev/null | grep -i "result\|status" | head -1)
    [ -n "$health" ] && lines+=("  $health") || lines+=("  Could not read SMART (need sudo)")

    local info
    info=$(sudo smartctl -i "$disk" 2>/dev/null)
    if [ -n "$info" ]; then
        local model serial fw
        model=$(echo "$info" | grep -i "Device Model\|Model Number" | head -1 | sed 's/.*: *//')
        serial=$(echo "$info" | grep -i "Serial Number" | head -1 | sed 's/.*: *//')
        fw=$(echo "$info" | grep -i "Firmware" | head -1 | sed 's/.*: *//')
        [ -n "$model" ] && lines+=("  Model: $model")
        [ -n "$serial" ] && lines+=("  Serial: $serial")
        [ -n "$fw" ] && lines+=("  Firmware: $fw")
    fi

    # Key SMART attributes
    local attrs
    attrs=$(sudo smartctl -A "$disk" 2>/dev/null)
    if [ -n "$attrs" ]; then
        lines+=("" "─── Key Attributes ───")
        local temp power_on reallocated wear
        temp=$(echo "$attrs" | grep -iE "Temperature_Celsius|Temperature" | head -1 | awk '{print $NF}')
        power_on=$(echo "$attrs" | grep -i "Power_On_Hours" | head -1 | awk '{print $NF}')
        reallocated=$(echo "$attrs" | grep -i "Reallocated_Sector" | head -1 | awk '{print $NF}')
        wear=$(echo "$attrs" | grep -iE "Wear_Leveling|Media_Wearout\|Percentage Used" | head -1 | awk '{print $NF}')

        [ -n "$temp" ] && lines+=("  Temperature: ${temp}°C")
        [ -n "$power_on" ] && lines+=("  Power-on hours: $power_on")
        [ -n "$reallocated" ] && lines+=("  Reallocated sectors: $reallocated")
        [ -n "$wear" ] && lines+=("  Wear level: $wear")
    fi

    printf '%s\n' "${lines[@]}" | _yad_pipe "  SMART"
}

# ── Mount / Unmount partitions ──
_disk_mount() {
    # List unmounted partitions
    local parts=()
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local name size fstype mount
        name=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $2}')
        fstype=$(echo "$line" | awk '{print $3}')
        mount=$(echo "$line" | awk '{print $4}')
        [ -z "$fstype" ] && continue
        [[ "$fstype" == "swap" ]] && continue
        [ -z "$mount" ] && parts+=("/dev/$name  $size  $fstype  (not mounted)")
    done < <(lsblk -lno NAME,SIZE,FSTYPE,MOUNTPOINT 2>/dev/null | grep -vE '^(loop|sr)')

    [ ${#parts[@]} -eq 0 ] && { _notify "No unmounted partitions found"; return; }

    local choice
    choice=$(printf '%s\n' "${parts[@]}" | _yad_pipe "  Mount partition")
    [ -z "$choice" ] && return

    local dev
    dev=$(echo "$choice" | awk '{print $1}')

    if command -v udisksctl &>/dev/null; then
        udisksctl mount -b "$dev" 2>&1 | head -1
        local mp
        mp=$(lsblk -no MOUNTPOINT "$dev" 2>/dev/null | head -1)
        _notify "Mounted $dev → $mp"
    else
        local mp="/mnt/$(basename "$dev")"
        sudo mkdir -p "$mp"
        sudo mount "$dev" "$mp" && _notify "Mounted $dev → $mp" || _notify "Mount failed"
    fi
}

_disk_unmount() {
    local parts=()
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local name size fstype mount
        name=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $2}')
        fstype=$(echo "$line" | awk '{print $3}')
        mount=$(echo "$line" | awk '{print $4}')
        [ -z "$mount" ] && continue
        [[ "$mount" == "/" ]] && continue
        [[ "$mount" == "/boot"* ]] && continue
        [[ "$mount" == "/home" ]] && continue
        parts+=("/dev/$name  $size  → $mount")
    done < <(lsblk -lno NAME,SIZE,FSTYPE,MOUNTPOINT 2>/dev/null | grep -vE '^(loop|sr)')

    [ ${#parts[@]} -eq 0 ] && { _notify "No unmountable partitions"; return; }

    local choice
    choice=$(printf '%s\n' "${parts[@]}" | _yad_pipe "  Unmount partition")
    [ -z "$choice" ] && return

    local dev
    dev=$(echo "$choice" | awk '{print $1}')

    _yad_confirm "Unmount $dev?" || return

    if command -v udisksctl &>/dev/null; then
        udisksctl unmount -b "$dev" 2>&1 | head -1
    else
        sudo umount "$dev" 2>/dev/null
    fi
    _notify "Unmounted $dev"
}

# ── Disk Usage Analyzer (du-based) ──
_disk_usage_scan() {
    local target
    target=$(_yad_select "  Analyze directory" \
        "  ~ (Home)" \
        "  / (Root)" \
        "  Custom path")
    [ -z "$target" ] && return

    case "$target" in
        *Home*)   target="$HOME" ;;
        *Root*)   target="/" ;;
        *Custom*) target=$(_yad_input "  Path to analyze")
                  [ -z "$target" ] && return
                  [ ! -d "$target" ] && { _notify "Not a directory: $target"; return; }
                  ;;
    esac

    _notify "Scanning $target..."

    local lines=()
    lines+=("─── Disk Usage: $target ───")
    lines+=("")

    # Top 20 largest subdirectories (depth 1)
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local size dir
        size=$(echo "$line" | awk '{print $1}')
        dir=$(echo "$line" | awk '{$1=""; print $0}' | xargs)
        lines+=("  $size    $dir")
    done < <(du -h --max-depth=1 "$target" 2>/dev/null | sort -rh | head -20)

    lines+=("")
    lines+=("─── Total ───")
    local total
    total=$(du -sh "$target" 2>/dev/null | awk '{print $1}')
    lines+=("  $total    $target")

    local selected
    selected=$(printf '%s\n' "${lines[@]}" | _yad_pipe "  Usage — select to drill down")

    # Drill-down: if user selects a directory, scan it recursively
    if [ -n "$selected" ]; then
        local subdir
        subdir=$(echo "$selected" | awk '{print $NF}')
        if [ -d "$subdir" ]; then
            _disk_usage_drill "$subdir"
        fi
    fi
}

_disk_usage_drill() {
    local target="$1"

    while true; do
        local lines=()
        lines+=("─── $target ───")
        lines+=("  ← Back")

        while IFS= read -r line; do
            [ -z "$line" ] && continue
            local size dir
            size=$(echo "$line" | awk '{print $1}')
            dir=$(echo "$line" | awk '{$1=""; print $0}' | xargs)
            [ "$dir" = "$target" ] && continue
            lines+=("  $size    $dir")
        done < <(du -h --max-depth=1 "$target" 2>/dev/null | sort -rh | head -25)

        local selected
        selected=$(printf '%s\n' "${lines[@]}" | _yad_pipe "  Usage")
        [ -z "$selected" ] && return
        [[ "$selected" == *"Back"* ]] && return

        local subdir
        subdir=$(echo "$selected" | awk '{print $NF}')
        if [ -d "$subdir" ]; then
            _disk_usage_drill "$subdir"
        fi
    done
}

# ── Largest files finder ──
_disk_largest_files() {
    local target
    target=$(_yad_select "  Find largest files" \
        "  ~ (Home)" \
        "  / (Root)" \
        "  Custom path")
    [ -z "$target" ] && return

    case "$target" in
        *Home*)   target="$HOME" ;;
        *Root*)   target="/" ;;
        *Custom*) target=$(_yad_input "  Path")
                  [ -z "$target" ] && return ;;
    esac

    _notify "Searching $target..."

    local lines=()
    lines+=("─── Largest Files in $target ───")

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local size file
        size=$(echo "$line" | awk '{print $1}')
        file=$(echo "$line" | awk '{$1=""; print $0}' | xargs)
        lines+=("  $size    $file")
    done < <(find "$target" -xdev -type f -exec du -h {} + 2>/dev/null | sort -rh | head -30)

    printf '%s\n' "${lines[@]}" | _yad_pipe "  Large Files"
}

# ── Filesystem check ──
_disk_fsck() {
    local parts=()
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local name size fstype mount
        name=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $2}')
        fstype=$(echo "$line" | awk '{print $3}')
        mount=$(echo "$line" | awk '{print $4}')
        [ -z "$fstype" ] && continue
        [[ "$fstype" == "swap" ]] && continue
        [ -n "$mount" ] && parts+=("/dev/$name  $size  $fstype  → $mount (mounted)") \
                        || parts+=("/dev/$name  $size  $fstype  (unmounted)")
    done < <(lsblk -lno NAME,SIZE,FSTYPE,MOUNTPOINT 2>/dev/null | grep -vE '^(loop|sr)')

    [ ${#parts[@]} -eq 0 ] && { _notify "No partitions found"; return; }

    local choice
    choice=$(printf '%s\n' "${parts[@]}" | _yad_pipe "  Filesystem check")
    [ -z "$choice" ] && return

    local dev
    dev=$(echo "$choice" | awk '{print $1}')

    if echo "$choice" | grep -q "mounted)"; then
        _notify "Cannot fsck mounted partition. Unmount first."
        return
    fi

    _yad_confirm "Run filesystem check on $dev?" || return

    local result
    result=$(sudo fsck -n "$dev" 2>&1)
    echo "$result" | _yad_pipe "  fsck $dev"
}

# ── Format partition (dangerous!) ──
_disk_format() {
    local parts=()
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local name size fstype mount
        name=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $2}')
        fstype=$(echo "$line" | awk '{print $3}')
        mount=$(echo "$line" | awk '{print $4}')
        [ -z "$fstype" ] && continue
        [[ "$fstype" == "swap" ]] && continue
        [ -n "$mount" ] && continue   # only unmounted
        parts+=("/dev/$name  $size  $fstype")
    done < <(lsblk -lno NAME,SIZE,FSTYPE,MOUNTPOINT 2>/dev/null | grep -vE '^(loop|sr)')

    [ ${#parts[@]} -eq 0 ] && { _notify "No unmounted partitions available"; return; }

    local choice
    choice=$(printf '%s\n' "${parts[@]}" | _yad_pipe "⚠ Format partition")
    [ -z "$choice" ] && return

    local dev
    dev=$(echo "$choice" | awk '{print $1}')

    local fs_choice
    fs_choice=$(_yad_select "  Filesystem for $dev" \
        "ext4" "btrfs" "xfs" "fat32 (vfat)" "ntfs" "exfat")
    [ -z "$fs_choice" ] && return

    _yad_confirm "FORMAT $dev as $fs_choice? ALL DATA WILL BE LOST!" || return
    _yad_confirm "Are you ABSOLUTELY sure? This is irreversible!" || return

    local mkfs_cmd
    case "$fs_choice" in
        ext4)          mkfs_cmd="mkfs.ext4" ;;
        btrfs)         mkfs_cmd="mkfs.btrfs -f" ;;
        xfs)           mkfs_cmd="mkfs.xfs -f" ;;
        "fat32 (vfat)") mkfs_cmd="mkfs.vfat -F 32" ;;
        ntfs)          mkfs_cmd="mkfs.ntfs -f" ;;
        exfat)         mkfs_cmd="mkfs.exfat" ;;
    esac

    _notify "Formatting $dev as $fs_choice..."
    if sudo $mkfs_cmd "$dev" 2>&1; then
        _notify "Formatted $dev as $fs_choice"
    else
        _notify "Format failed!"
    fi
}

# ── Set partition label ──
_disk_label() {
    local parts=()
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local name size fstype label
        name=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $2}')
        fstype=$(echo "$line" | awk '{print $3}')
        label=$(echo "$line" | awk '{print $4}')
        [ -z "$fstype" ] && continue
        [ -n "$label" ] && parts+=("/dev/$name  $size  $fstype  [$label]") \
                        || parts+=("/dev/$name  $size  $fstype  (no label)")
    done < <(lsblk -lno NAME,SIZE,FSTYPE,LABEL 2>/dev/null | grep -vE '^(loop|sr)')

    [ ${#parts[@]} -eq 0 ] && { _notify "No partitions found"; return; }

    local choice
    choice=$(printf '%s\n' "${parts[@]}" | _yad_pipe "  Set label")
    [ -z "$choice" ] && return

    local dev fstype
    dev=$(echo "$choice" | awk '{print $1}')
    fstype=$(echo "$choice" | awk '{print $3}')

    local new_label
    new_label=$(_yad_input "  New label for $dev")
    [ -z "$new_label" ] && return

    case "$fstype" in
        ext2|ext3|ext4) sudo e2label "$dev" "$new_label" ;;
        btrfs)          sudo btrfs filesystem label "$dev" "$new_label" ;;
        xfs)            sudo xfs_admin -L "$new_label" "$dev" ;;
        vfat)           sudo fatlabel "$dev" "$new_label" ;;
        ntfs)           sudo ntfslabel "$dev" "$new_label" ;;
        exfat)          sudo exfatlabel "$dev" "$new_label" ;;
        *)              _notify "Cannot set label for $fstype"; return ;;
    esac
    _notify "Label set: $dev → $new_label"
}

# ── Benchmark (simple sequential read test) ──
_disk_benchmark() {
    local disks=()
    while IFS= read -r d; do
        [ -n "$d" ] && disks+=("/dev/$d")
    done < <(lsblk -dno NAME 2>/dev/null | grep -E '^(sd|nvme|vd)')

    [ ${#disks[@]} -eq 0 ] && { _notify "No disks found"; return; }

    local disk
    if [ ${#disks[@]} -eq 1 ]; then
        disk="${disks[0]}"
    else
        disk=$(printf '%s\n' "${disks[@]}" | _yad_pipe "  Benchmark disk")
        [ -z "$disk" ] && return
    fi

    _yad_confirm "Run sequential read test on $disk? (read-only, safe)" || return
    _notify "Benchmarking $disk... (this takes a few seconds)"

    local result
    result=$(sudo hdparm -tT "$disk" 2>/dev/null)
    if [ -z "$result" ]; then
        # Fallback with dd
        result=$(sudo dd if="$disk" of=/dev/null bs=1M count=512 2>&1 | tail -1)
    fi

    local lines=()
    lines+=("─── Benchmark: $disk ───")
    while IFS= read -r line; do
        [ -n "$line" ] && lines+=("  $line")
    done <<< "$result"

    printf '%s\n' "${lines[@]}" | _yad_pipe "  Benchmark"
}

# ── Manage fstab (show + edit) ──
_disk_fstab() {
    local choice
    choice=$(_yad_select "  /etc/fstab" \
        "  View fstab" \
        "  Add current mounts to fstab" \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    case "$choice" in
        *View*)
            cat /etc/fstab 2>/dev/null | _yad_pipe "  fstab"
            ;;
        *Add*)
            # Show non-fstab mounts that could be added
            local mounts=()
            while IFS= read -r line; do
                [ -z "$line" ] && continue
                local dev mount fstype
                dev=$(echo "$line" | awk '{print $1}')
                mount=$(echo "$line" | awk '{print $6}')
                fstype=$(findmnt -no FSTYPE "$mount" 2>/dev/null)
                [[ "$dev" == /dev/* ]] || continue
                [[ "$mount" == "/" ]] && continue
                [[ "$mount" == "/boot"* ]] && continue
                # Check if already in fstab
                grep -q "$dev\|$mount" /etc/fstab 2>/dev/null && continue
                local uuid
                uuid=$(blkid -s UUID -o value "$dev" 2>/dev/null)
                [ -n "$uuid" ] && mounts+=("UUID=$uuid  $mount  $fstype  defaults  0 2")
            done < <(df 2>/dev/null | tail -n +2)

            if [ ${#mounts[@]} -eq 0 ]; then
                _notify "All current mounts already in fstab"
                return
            fi

            local entry
            entry=$(printf '%s\n' "${mounts[@]}" | _yad_pipe "  Add to fstab")
            [ -z "$entry" ] && return

            _yad_confirm "Add to /etc/fstab?\n$entry" || return
            echo "$entry" | sudo tee -a /etc/fstab >/dev/null
            _notify "Entry added to fstab"
            ;;
    esac
}

# ── Cleanup helper: find junk ──
_disk_cleanup() {
    local lines=()
    lines+=("─── Cleanup Opportunities ───")
    lines+=("")

    # Package cache
    local pkg_cache
    pkg_cache=$(du -sh /var/cache/pacman/pkg/ 2>/dev/null | awk '{print $1}')
    lines+=("  Package cache: ${pkg_cache:-?}")

    # Journal
    local journal
    journal=$(journalctl --disk-usage 2>/dev/null | grep -oP '[0-9.]+[KMGT]')
    lines+=("  System journal: ${journal:-?}")

    # Trash
    local trash_size="0"
    [ -d "${HOME}/.local/share/Trash/files" ] && \
        trash_size=$(du -sh "${HOME}/.local/share/Trash/files" 2>/dev/null | awk '{print $1}')
    lines+=("  Trash: ${trash_size}")

    # Orphaned packages
    local orphans
    orphans=$(pacman -Qtdq 2>/dev/null | wc -l)
    lines+=("  Orphaned packages: $orphans")

    # Thumbnails
    local thumbnails="0"
    [ -d "${HOME}/.cache/thumbnails" ] && \
        thumbnails=$(du -sh "${HOME}/.cache/thumbnails" 2>/dev/null | awk '{print $1}')
    lines+=("  Thumbnails cache: $thumbnails")

    lines+=("")
    lines+=("─── Actions ───")
    lines+=("  Clean package cache (keep last 3)")
    lines+=("  Clean journal (keep 2 weeks)")
    lines+=("  Empty trash")
    lines+=("  Remove orphaned packages")

    local choice
    choice=$(printf '%s\n' "${lines[@]}" | _yad_pipe "  Cleanup")
    [ -z "$choice" ] && return

    case "$choice" in
        *"package cache"*)
            if command -v paccache &>/dev/null; then
                _yad_confirm "Clean package cache? (keep last 3 versions)" || return
                sudo paccache -r 2>&1 | tail -1
                _notify "Package cache cleaned"
            else
                _notify "paccache not found (pacman-contrib)"
            fi
            ;;
        *journal*)
            _yad_confirm "Vacuum journal to 2 weeks?" || return
            sudo journalctl --vacuum-time=2weeks 2>&1 | tail -1
            _notify "Journal cleaned"
            ;;
        *trash*)
            _yad_confirm "Empty trash?" || return
            rm -rf "${HOME}/.local/share/Trash/files/"* "${HOME}/.local/share/Trash/info/"*
            _notify "Trash emptied"
            ;;
        *orphaned*)
            local pkgs
            pkgs=$(pacman -Qtdq 2>/dev/null)
            [ -z "$pkgs" ] && { _notify "No orphaned packages"; return; }
            _yad_confirm "Remove orphaned packages?\n$(echo "$pkgs" | head -10)" || return
            echo "$pkgs" | sudo pacman -Rns - 2>&1 | tail -3
            _notify "Orphaned packages removed"
            ;;
    esac
}

# ── Disk Manager menu ──
menu_disks() {
    while true; do
        # Get summary
        local total used avail pct
        read -r total used avail pct < <(df -h --total 2>/dev/null | grep '^total' | awk '{print $2, $3, $4, $5}')

        local choice
        choice=$(_yad_select "  Disks & Storage (${used:-?}/${total:-?} — ${pct:-?})" \
            "  Overview" \
            "  Disk Usage Analyzer" \
            "  Largest Files" \
            "  Mount Partition" \
            "  Unmount Partition" \
            "  SMART Health" \
            "  Benchmark" \
            "  Filesystem Check" \
            "  Format Partition" \
            "  Set Label" \
            "  fstab" \
            "  Cleanup" \
            "  Disk Utility (gnome-disks)" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *Overview*)      _disk_overview | _yad_pipe "  Disks" ;;
            *Analyzer*)      _disk_usage_scan ;;
            *"Largest Files"*) _disk_largest_files ;;
            *"Mount P"*)     _disk_mount ;;
            *"Unmount"*)     _disk_unmount ;;
            *SMART*)         _disk_smart ;;
            *Benchmark*)     _disk_benchmark ;;
            *"Filesystem"*)  _disk_fsck ;;
            *Format*)        _disk_format ;;
            *Label*)         _disk_label ;;
            *fstab*)         _disk_fstab ;;
            *Cleanup*)       _disk_cleanup ;;
            *"Disk Utility"*)
                if command -v gnome-disks &>/dev/null; then
                    gnome-disks & disown
                else
                    _notify "gnome-disk-utility not installed"
                fi
                ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════
#   SYSTEM HEALTH (stoa-doctor integration)
# ══════════════════════════════════════════════════════════════

# ── Run doctor and show results ──
_health_doctor() {
    _notify "Running health check..."
    stoa-doctor 2>/dev/null
    local log="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/doctor.log"
    if [ -f "$log" ]; then
        cat "$log" | _yad_pipe "  Doctor Report"
    else
        _notify "No doctor log found"
    fi
}

# ── View last doctor log ──
_health_last_log() {
    local log="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/doctor.log"
    if [ -f "$log" ]; then
        cat "$log" | _yad_pipe "  Last Report"
    else
        _notify "No doctor log found — run health check first"
    fi
}

# ── Package snapshots ──
_health_pkg_snapshots() {
    local snap_dir="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/pkg-snapshots"
    mkdir -p "$snap_dir"

    local snaps=()
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        local name size
        name=$(basename "$f")
        size=$(wc -l < "$f" 2>/dev/null)
        snaps+=("$name  ($size packages)")
    done < <(ls -1t "$snap_dir"/pkg-snapshot-*.txt 2>/dev/null)

    [ ${#snaps[@]} -eq 0 ] && { _notify "No snapshots yet — they're created before pacman transactions"; return; }

    local choice
    choice=$(printf '%s\n' "${snaps[@]}" | _yad_pipe "  Snapshots (${#snaps[@]})")
    [ -z "$choice" ] && return

    local selected_file
    selected_file="$snap_dir/$(echo "$choice" | awk '{print $1}')"
    [ ! -f "$selected_file" ] && return

    local action
    action=$(_yad_select "  $choice" \
        "  View snapshot" \
        "  Compare with current" \
        "  Compare two snapshots" \
        "  Back")
    [ -z "$action" ] || [[ "$action" == *"Back"* ]] && return

    case "$action" in
        *"View"*)
            cat "$selected_file" | _yad_pipe "  Snapshot"
            ;;
        *"with current"*)
            local lines=()
            lines+=("─── Changes since $(basename "$selected_file" .txt) ───")
            lines+=("")

            # Packages added since snapshot
            local added
            added=$(diff <(awk '{print $1}' "$selected_file" | grep -v '^#' | sort) \
                         <(pacman -Qq 2>/dev/null | sort) \
                    | grep '^>' | sed 's/^> //' )
            if [ -n "$added" ]; then
                lines+=("─── Added ───")
                while IFS= read -r pkg; do
                    local ver
                    ver=$(pacman -Q "$pkg" 2>/dev/null | awk '{print $2}')
                    lines+=("  + $pkg  $ver")
                done <<< "$added"
                lines+=("")
            fi

            # Packages removed since snapshot
            local removed
            removed=$(diff <(awk '{print $1}' "$selected_file" | grep -v '^#' | sort) \
                           <(pacman -Qq 2>/dev/null | sort) \
                      | grep '^<' | sed 's/^< //')
            if [ -n "$removed" ]; then
                lines+=("─── Removed ───")
                while IFS= read -r pkg; do
                    lines+=("  − $pkg")
                done <<< "$removed"
                lines+=("")
            fi

            # Packages with version changes
            local changed
            changed=$(diff <(grep -v '^#' "$selected_file" | sort) \
                           <(pacman -Q 2>/dev/null | sort) \
                     | grep '^[<>]' | grep -v '^---' || true)
            if [ -n "$changed" ]; then
                local upgrades=()
                while IFS= read -r pkg_name; do
                    local old_ver new_ver
                    old_ver=$(grep "^$pkg_name " "$selected_file" 2>/dev/null | awk '{print $2}')
                    new_ver=$(pacman -Q "$pkg_name" 2>/dev/null | awk '{print $2}')
                    [ -n "$old_ver" ] && [ -n "$new_ver" ] && [ "$old_ver" != "$new_ver" ] && \
                        upgrades+=("  ↑ $pkg_name  $old_ver → $new_ver")
                done < <(diff <(awk '{print $1}' "$selected_file" | grep -v '^#' | sort) \
                              <(pacman -Qq 2>/dev/null | sort) \
                         | grep -v '^[<>]' | grep -v '^---' || \
                         comm -12 <(awk '{print $1}' "$selected_file" | grep -v '^#' | sort) \
                                  <(pacman -Qq 2>/dev/null | sort))
                if [ ${#upgrades[@]} -gt 0 ]; then
                    lines+=("─── Upgraded ───")
                    for u in "${upgrades[@]}"; do
                        lines+=("$u")
                    done
                fi
            fi

            [ ${#lines[@]} -le 2 ] && lines+=("  No changes detected")

            printf '%s\n' "${lines[@]}" | _yad_pipe "  Diff"
            ;;
        *"two snapshots"*)
            local snap2
            snap2=$(printf '%s\n' "${snaps[@]}" | _yad_pipe "  Compare with")
            [ -z "$snap2" ] && return
            local file2="$snap_dir/$(echo "$snap2" | awk '{print $1}')"
            [ ! -f "$file2" ] && return

            local lines=()
            lines+=("─── $(basename "$selected_file") vs $(basename "$file2") ───")
            lines+=("")

            local d
            d=$(diff <(grep -v '^#' "$selected_file" | sort) \
                      <(grep -v '^#' "$file2" | sort) || true)
            if [ -z "$d" ]; then
                lines+=("  Identical snapshots")
            else
                while IFS= read -r line; do
                    case "$line" in
                        "< "*) lines+=("  − ${line#< }") ;;
                        "> "*) lines+=("  + ${line#> }") ;;
                    esac
                done <<< "$d"
            fi

            printf '%s\n' "${lines[@]}" | _yad_pipe "  Diff"
            ;;
    esac
}

# ── System uptime & kernel ──
_health_system_info() {
    local lines=()
    lines+=("─── System ───")
    lines+=("  Hostname: $(hostname)")
    lines+=("  Kernel: $(uname -r)")
    lines+=("  Arch: $(uname -m)")
    lines+=("  Uptime: $(uptime -p 2>/dev/null | sed 's/^up //')")
    lines+=("  Boot: $(who -b 2>/dev/null | awk '{print $3, $4}')")
    lines+=("")

    # WM info
    local hypr_ver
    hypr_ver=$(cat "${XDG_CONFIG_HOME:-$HOME/.config}/stoa/hyprland-version" 2>/dev/null || echo "?")
    lines+=("  Session: Wayland (Hyprland $hypr_ver)")

    # Shell
    lines+=("  Shell: $SHELL")

    # Locale
    local lang
    lang=$(locale 2>/dev/null | grep "^LANG=" | cut -d= -f2)
    lines+=("  Locale: $lang")

    lines+=("")
    lines+=("─── Packages ───")
    lines+=("  Total: $(pacman -Qq 2>/dev/null | wc -l)")
    lines+=("  Explicit: $(pacman -Qqe 2>/dev/null | wc -l)")
    lines+=("  Dependencies: $(pacman -Qqd 2>/dev/null | wc -l)")
    lines+=("  AUR/foreign: $(pacman -Qqm 2>/dev/null | wc -l)")
    lines+=("  Orphans: $(pacman -Qqtd 2>/dev/null | wc -l)")

    printf '%s\n' "${lines[@]}" | _yad_pipe "  System"
}

# ── Services status ──
_health_services() {
    local lines=()
    lines+=("─── Critical Services ───")

    local services=(
        "pipewire:PipeWire (audio)"
        "pipewire-pulse:PipeWire-Pulse"
        "wireplumber:WirePlumber (audio routing)"
        "NetworkManager:NetworkManager"
        "bluetooth:Bluetooth"
        "cups:CUPS (printing)"
        "nftables:Firewall (nftables)"
        "power-profiles-daemon:Power Profiles"
    )

    for entry in "${services[@]}"; do
        local svc name status
        svc="${entry%%:*}"
        name="${entry#*:}"

        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            status="● running"
        elif systemctl --user is-active --quiet "$svc" 2>/dev/null; then
            status="● running (user)"
        elif systemctl is-enabled --quiet "$svc" 2>/dev/null; then
            status="○ enabled (not running)"
        else
            status="✕ inactive"
        fi
        lines+=("  $status    $name")
    done

    lines+=("")
    lines+=("─── Stoa Processes ───")

    local stoa_procs=("noctalia" "eww" "gammastep")
    for proc in "${stoa_procs[@]}"; do
        if pgrep -x "$proc" &>/dev/null; then
            lines+=("  ● running    $proc")
        else
            lines+=("  ○ stopped    $proc")
        fi
    done

    printf '%s\n' "${lines[@]}" | _yad_pipe "  Services"
}

# ── Failed systemd units ──
_health_failed_units() {
    local lines=()
    lines+=("─── Failed Units ───")

    local failed
    failed=$(systemctl --failed --no-legend 2>/dev/null)
    local user_failed
    user_failed=$(systemctl --user --failed --no-legend 2>/dev/null)

    if [ -z "$failed" ] && [ -z "$user_failed" ]; then
        lines+=("  All units OK — no failures")
    else
        if [ -n "$failed" ]; then
            lines+=("" "─── System ───")
            while IFS= read -r line; do
                [ -n "$line" ] && lines+=("  ✕ $line")
            done <<< "$failed"
        fi
        if [ -n "$user_failed" ]; then
            lines+=("" "─── User ───")
            while IFS= read -r line; do
                [ -n "$line" ] && lines+=("  ✕ $line")
            done <<< "$user_failed"
        fi
    fi

    printf '%s\n' "${lines[@]}" | _yad_pipe "  Failed Units"
}

# ── Journal errors (recent) ──
_health_journal() {
    local choice
    choice=$(_yad_select "  Journal" \
        "  Errors (last boot)" \
        "  Warnings (last boot)" \
        "  Kernel messages (dmesg)" \
        "  Journal disk usage" \
        "  Back")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    case "$choice" in
        *Errors*)
            journalctl -b -p err --no-pager -n 100 2>/dev/null | _yad_pipe "  Errors"
            ;;
        *Warnings*)
            journalctl -b -p warning --no-pager -n 100 2>/dev/null | _yad_pipe "  Warnings"
            ;;
        *Kernel*)
            dmesg --level=err,warn -T 2>/dev/null | tail -80 | _yad_pipe "  dmesg"
            ;;
        *"disk usage"*)
            journalctl --disk-usage 2>/dev/null | _yad_pipe "  Journal"
            ;;
    esac
}

# ── Pacman: pending updates ──
_health_updates() {
    _notify "Checking for updates..."
    local updates
    updates=$(checkupdates 2>/dev/null)

    if [ -z "$updates" ]; then
        _notify "System is up to date"
        return
    fi

    local count
    count=$(echo "$updates" | wc -l)

    local lines=()
    lines+=("─── $count updates available ───")
    lines+=("")
    while IFS= read -r line; do
        lines+=("  $line")
    done <<< "$updates"

    local choice
    choice=$(printf '%s\n' "${lines[@]}" | _yad_pipe "  Updates ($count)")

    # Offer to update
    if [ -n "$choice" ]; then
        _yad_confirm "Run system update? (sudo pacman -Syu)" || return
        kitty --hold -e sudo pacman -Syu &
        disown
    fi
}

# ── Security: check for known vulnerable packages ──
_health_security() {
    local lines=()
    lines+=("─── Security ───")

    # Check if any packages have known vulnerabilities via arch-audit
    if command -v arch-audit &>/dev/null; then
        local vulns
        vulns=$(arch-audit 2>/dev/null)
        if [ -z "$vulns" ]; then
            lines+=("  No known vulnerabilities")
        else
            lines+=("")
            while IFS= read -r v; do
                lines+=("  ⚠ $v")
            done <<< "$vulns"
        fi
    else
        lines+=("  arch-audit not installed")
        lines+=("  Install: sudo pacman -S arch-audit")
    fi

    lines+=("")
    lines+=("─── GPG Keys ───")
    if command -v gpg &>/dev/null; then
        local key_count
        key_count=$(gpg --list-keys 2>/dev/null | grep -c "^pub" || echo "0")
        lines+=("  GPG keys in keyring: $key_count")

        local pacman_keys
        pacman_keys=$(pacman-key --list-keys 2>/dev/null | grep -c "^pub" || echo "?")
        lines+=("  Pacman keyring: $pacman_keys keys")
    else
        lines+=("  gnupg not installed")
    fi

    lines+=("")
    lines+=("─── Firewall ───")
    if command -v nft &>/dev/null; then
        if sudo nft list ruleset 2>/dev/null | grep -q "chain"; then
            lines+=("  ● nftables active")
            local rules
            rules=$(sudo nft list ruleset 2>/dev/null | grep -c "rule" || echo "0")
            lines+=("  Rules loaded: $rules")
        else
            lines+=("  ○ nftables — no rules loaded")
        fi
    else
        lines+=("  ✕ nftables not installed")
    fi

    printf '%s\n' "${lines[@]}" | _yad_pipe "  Security"
}

# ── Temperatures & fans ──
_health_thermals() {
    local lines=()
    lines+=("─── Temperatures ───")

    # CPU thermal zones
    for tz in /sys/class/thermal/thermal_zone*; do
        [ -d "$tz" ] || continue
        local type temp
        type=$(cat "$tz/type" 2>/dev/null)
        temp=$(cat "$tz/temp" 2>/dev/null)
        [ -n "$temp" ] && lines+=("  $type: $((temp / 1000))°C")
    done

    # hwmon sensors
    if command -v sensors &>/dev/null; then
        lines+=("")
        lines+=("─── Sensors ───")
        while IFS= read -r line; do
            [ -n "$line" ] && lines+=("  $line")
        done < <(sensors 2>/dev/null)
    else
        lines+=("")
        lines+=("  lm_sensors not installed — install: sudo pacman -S lm_sensors")
    fi

    # Fans
    local fans_found=false
    for hwmon in /sys/class/hwmon/hwmon*; do
        for fan in "$hwmon"/fan*_input; do
            [ -f "$fan" ] || continue
            fans_found=true
            local rpm label
            rpm=$(cat "$fan" 2>/dev/null)
            label=$(cat "${fan%_input}_label" 2>/dev/null || basename "$fan" | sed 's/_input//')
            lines+=("  Fan $label: ${rpm} RPM")
        done
    done
    $fans_found || lines+=("  No fan sensors detected")

    printf '%s\n' "${lines[@]}" | _yad_pipe "  Thermals"
}

# ── Stoa config files integrity ──
_health_config_check() {
    local lines=()
    lines+=("─── Config Files ───")

    local configs=(
        "${HOME}/.config/hypr/hyprland.lua:Hyprland config"
        "${HOME}/.config/noctalia/config.toml:Noctalia config"
        "${HOME}/.config/kitty/kitty.conf:Kitty config"
        "${HOME}/.config/eww/eww.yuck:EWW widgets"
        "${HOME}/.config/eww/eww.scss:EWW styles"
        "${HOME}/.config/stoa/stoa.conf:Stoa config"
    )

    for entry in "${configs[@]}"; do
        local path name status
        path="${entry%%:*}"
        name="${entry#*:}"

        if [ -L "$path" ]; then
            local target
            target=$(readlink -f "$path" 2>/dev/null)
            if [ -f "$target" ]; then
                status="● symlink OK"
            else
                status="✕ broken symlink → $target"
            fi
        elif [ -f "$path" ]; then
            status="● file (not symlinked)"
        else
            status="✕ missing"
        fi
        lines+=("  $status    $name")
    done

    printf '%s\n' "${lines[@]}" | _yad_pipe "  Configs"
}

# ── System Health menu ──
menu_health() {
    while true; do
        local choice
        choice=$(_yad_select "  System Health" \
            "  Run Health Check" \
            "  Last Doctor Report" \
            "  System Info" \
            "  Services Status" \
            "  Failed Units" \
            "  Temperatures & Fans" \
            "  Journal (errors/warnings)" \
            "  Pending Updates" \
            "  Package Snapshots" \
            "  Security" \
            "  Config Integrity" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *"Run Health"*)     _health_doctor ;;
            *"Last Doctor"*)    _health_last_log ;;
            *"System Info"*)    _health_system_info ;;
            *"Services"*)       _health_services ;;
            *"Failed"*)         _health_failed_units ;;
            *"Temperatures"*)   _health_thermals ;;
            *"Journal"*)        _health_journal ;;
            *"Updates"*)        _health_updates ;;
            *"Snapshots"*)      _health_pkg_snapshots ;;
            *"Security"*)       _health_security ;;
            *"Config"*)         _health_config_check ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════
#   MAINTENANCE (backup, restore, cleanup — BRCS integration)
# ══════════════════════════════════════════════════════════════

_maintain_log="${HOME}/backup_$(date +%Y%m%d).log"

_maintain_log_msg() {
    local level="$1"; shift
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$ts] [$level] $*" >> "$_maintain_log" 2>/dev/null
}

# ── Backup configurations ──
_maintain_backup() {
    if ! command -v zip &>/dev/null; then
        _notify "zip not installed (pacman -S zip)"
        return
    fi

    _yad_confirm "Backup all system & user configs?" || return
    _notify "Backing up configurations..."

    local hostname_str="${HOSTNAME:-$(hostname 2>/dev/null || echo unknown)}"
    local today=$(date +%Y%m%d)
    local arq="${HOME}/${hostname_str}.confs.${today}.zip"
    local all_files=""

    # /etc/ config files
    for ext in .conf .ini .rules; do
        local found
        found=$(find /etc -name "*${ext}" -type f 2>/dev/null)
        [ -n "$found" ] && all_files+="$found"$'\n'
    done

    # System files
    for sysfile in /etc/fstab /etc/default/grub /etc/hostname /etc/resolv.conf /etc/hosts /etc/locale.conf /etc/vconsole.conf /etc/environment; do
        [ -f "$sysfile" ] && all_files+="$sysfile"$'\n'
    done

    # User dotfiles
    for dotfile in .bashrc .bash_profile .bash_aliases .profile .zshrc .zprofile .vimrc .nanorc .gitconfig .tmux.conf .inputrc; do
        [ -f "$HOME/$dotfile" ] && all_files+="$HOME/$dotfile"$'\n'
    done

    # User config directory (shallow)
    if [ -d "$HOME/.config" ]; then
        local cfg_files
        cfg_files=$(find "$HOME/.config" -maxdepth 3 -type f \( -name '*.conf' -o -name '*.ini' -o -name '*.yml' -o -name '*.yaml' \) 2>/dev/null)
        [ -n "$cfg_files" ] && all_files+="$cfg_files"$'\n'
    fi

    # Crontabs
    for crontab_path in "/var/spool/cron/crontabs/$(whoami)" "/var/spool/cron/$(whoami)" /etc/crontab; do
        [ -f "$crontab_path" ] && all_files+="$crontab_path"$'\n'
    done
    if [ -d /etc/cron.d ]; then
        local cron_files
        cron_files=$(find /etc/cron.d -type f 2>/dev/null)
        [ -n "$cron_files" ] && all_files+="$cron_files"$'\n'
    fi

    # Systemd custom units
    for unit_dir in /etc/systemd/system /etc/systemd/user "$HOME/.config/systemd/user"; do
        if [ -d "$unit_dir" ]; then
            local unit_files
            unit_files=$(find "$unit_dir" -maxdepth 2 -type f \( -name '*.service' -o -name '*.timer' -o -name '*.mount' -o -name '*.target' -o -name '*.socket' \) 2>/dev/null)
            [ -n "$unit_files" ] && all_files+="$unit_files"$'\n'
        fi
    done

    # SSH config (never backup private keys)
    for ssh_file in "$HOME/.ssh/config" "$HOME/.ssh/authorized_keys" /etc/ssh/sshd_config /etc/ssh/ssh_config; do
        [ -f "$ssh_file" ] && all_files+="$ssh_file"$'\n'
    done

    # Firewall rules
    for fw_file in /etc/iptables/rules.v4 /etc/iptables/rules.v6 /etc/nftables.conf /etc/firewalld/firewalld.conf /etc/ufw/ufw.conf; do
        [ -f "$fw_file" ] && all_files+="$fw_file"$'\n'
    done

    # Network configs
    for net_dir in /etc/NetworkManager/system-connections /etc/netplan /etc/systemd/network; do
        if [ -d "$net_dir" ]; then
            local net_files
            net_files=$(find "$net_dir" -type f 2>/dev/null)
            [ -n "$net_files" ] && all_files+="$net_files"$'\n'
        fi
    done

    # Pacman config
    for repo_path in /etc/pacman.conf /etc/pacman.d; do
        if [ -f "$repo_path" ]; then
            all_files+="$repo_path"$'\n'
        elif [ -d "$repo_path" ]; then
            local repo_files
            repo_files=$(find "$repo_path" -type f 2>/dev/null)
            [ -n "$repo_files" ] && all_files+="$repo_files"$'\n'
        fi
    done

    # Shell scripts in user home
    local found_sh
    found_sh=$(find "$HOME" -maxdepth 2 -name "*.sh" -type f 2>/dev/null)
    [ -n "$found_sh" ] && all_files+="$found_sh"$'\n'

    # Remove empty lines and duplicates
    all_files=$(echo "$all_files" | sort -u | sed '/^$/d')

    if [ -z "$all_files" ]; then
        _notify "No configuration files found"
        return
    fi

    local file_count
    file_count=$(echo "$all_files" | wc -l)

    echo "$all_files" | zip "$arq" -r -9 -@ >> "$_maintain_log" 2>&1

    local archive_size
    archive_size=$(du -h "$arq" 2>/dev/null | cut -f1)
    _maintain_log_msg INFO "Backup saved: $arq ($file_count files, $archive_size)"
    _notify "Backup saved: $(basename "$arq") ($file_count files, $archive_size)"
}

# ── List backup contents ──
_maintain_list() {
    local backups=()
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        local name size
        name=$(basename "$f")
        size=$(du -h "$f" 2>/dev/null | cut -f1)
        backups+=("$name  ($size)")
    done < <(ls -1t "$HOME"/*.confs.*.zip 2>/dev/null)

    [ ${#backups[@]} -eq 0 ] && { _notify "No backups found in \$HOME"; return; }

    local choice
    choice=$(printf '%s\n' "${backups[@]}" | _yad_pipe "  Backups (${#backups[@]})")
    [ -z "$choice" ] && return

    local selected_file
    selected_file="$HOME/$(echo "$choice" | awk '{print $1}')"
    [ ! -f "$selected_file" ] && return

    local action
    action=$(_yad_select "  $(basename "$selected_file")" \
        "  View contents" \
        "  Restore (interactive)" \
        "  Restore all" \
        "  Back")
    [ -z "$action" ] || [[ "$action" == *"Back"* ]] && return

    case "$action" in
        *"View"*)
            unzip -l "$selected_file" 2>/dev/null | _yad_pipe "  Contents"
            ;;
        *"interactive"*)
            _maintain_restore_interactive "$selected_file"
            ;;
        *"Restore all"*)
            _maintain_restore_all "$selected_file"
            ;;
    esac
}

# ── Restore interactive ──
_maintain_restore_interactive() {
    local backup_file="$1"
    if ! command -v unzip &>/dev/null; then
        _notify "unzip not installed (pacman -S unzip)"
        return
    fi

    if ! unzip -t "$backup_file" >/dev/null 2>&1; then
        _notify "Invalid or corrupted zip file"
        return
    fi

    local tmpdir
    tmpdir=$(mktemp -d)
    unzip -o "$backup_file" -d "$tmpdir" >/dev/null 2>&1

    # Safety backup
    local pre_restore="$HOME/pre_restore_$(date +%Y%m%d_%H%M%S).zip"
    local existing=()
    while IFS= read -r -d '' f; do
        local dest="/${f#"$tmpdir"/}"
        [ -f "$dest" ] && existing+=("$dest")
    done < <(find "$tmpdir" -type f -print0 2>/dev/null)

    if [ ${#existing[@]} -gt 0 ] && command -v zip &>/dev/null; then
        zip -q "$pre_restore" "${existing[@]}" 2>/dev/null || true
        _notify "Safety backup: $(basename "$pre_restore")"
    fi

    # Build file list for yad selection
    local files=()
    while IFS= read -r -d '' f; do
        local dest="/${f#"$tmpdir"/}"
        files+=("$dest")
    done < <(find "$tmpdir" -type f -print0 2>/dev/null)

    local restored=0 skipped=0
    for dest in "${files[@]}"; do
        local src="${tmpdir}${dest}"
        local status="NEW"
        [ -f "$dest" ] && status="EXISTS"

        local confirm
        confirm=$(_yad_select "  [$status] $dest" "  Restore" "  Skip")
        if [[ "$confirm" == *"Restore"* ]]; then
            sudo mkdir -p "$(dirname "$dest")"
            sudo cp "$src" "$dest"
            restored=$((restored + 1))
        else
            skipped=$((skipped + 1))
        fi
    done

    rm -rf "$tmpdir"
    _notify "Restore done: $restored restored, $skipped skipped"
}

# ── Restore all (no prompt) ──
_maintain_restore_all() {
    local backup_file="$1"
    if ! command -v unzip &>/dev/null; then
        _notify "unzip not installed (pacman -S unzip)"
        return
    fi

    _yad_confirm "Restore ALL files from $(basename "$backup_file")? This overwrites existing files." || return

    if ! unzip -t "$backup_file" >/dev/null 2>&1; then
        _notify "Invalid or corrupted zip file"
        return
    fi

    local tmpdir
    tmpdir=$(mktemp -d)
    unzip -o "$backup_file" -d "$tmpdir" >/dev/null 2>&1

    # Safety backup
    local pre_restore="$HOME/pre_restore_$(date +%Y%m%d_%H%M%S).zip"
    local existing=()
    while IFS= read -r -d '' f; do
        local dest="/${f#"$tmpdir"/}"
        [ -f "$dest" ] && existing+=("$dest")
    done < <(find "$tmpdir" -type f -print0 2>/dev/null)

    if [ ${#existing[@]} -gt 0 ] && command -v zip &>/dev/null; then
        zip -q "$pre_restore" "${existing[@]}" 2>/dev/null || true
    fi

    local count=0
    while IFS= read -r -d '' f; do
        local dest="/${f#"$tmpdir"/}"
        sudo mkdir -p "$(dirname "$dest")"
        sudo cp "$f" "$dest"
        count=$((count + 1))
    done < <(find "$tmpdir" -type f -print0 2>/dev/null)

    rm -rf "$tmpdir"
    _notify "Restored $count files (safety backup: $(basename "$pre_restore"))"
}

# ── Full system cleanup ──
_maintain_cleanup() {
    local dry_run="${1:-0}"
    local mode="Cleanup"
    [ "$dry_run" -eq 1 ] && mode="Cleanup (dry-run)"

    _yad_confirm "Run full system cleanup? Includes package cache, orphans, journal, flatpak, docker, Steam cache, tmp files." || return
    _notify "Running $mode..."

    local space_before
    space_before=$(df / | awk 'NR==2{print $3}')

    local log_lines=()
    log_lines+=("─── System $mode ───")
    log_lines+=("")

    # 1. Update & upgrade
    log_lines+=("  [1/10] Package update")
    if [ "$dry_run" -eq 0 ]; then
        sudo pacman -Syu --noconfirm >> "$_maintain_log" 2>&1 && \
            log_lines+=("    ✓ System updated") || \
            log_lines+=("    ✕ Update failed — check log")
    else
        log_lines+=("    [DRY-RUN] Would run: pacman -Syu")
    fi

    # 2. Clean package cache
    log_lines+=("  [2/10] Package cache")
    if [ "$dry_run" -eq 0 ]; then
        if command -v paccache &>/dev/null; then
            local cleaned
            cleaned=$(sudo paccache -rk1 2>&1 | tail -1)
            log_lines+=("    ✓ $cleaned")
        else
            sudo pacman -Sc --noconfirm >> "$_maintain_log" 2>&1
            log_lines+=("    ✓ Cache cleaned")
        fi
    else
        log_lines+=("    [DRY-RUN] Would clean package cache")
    fi

    # 3. Remove orphan packages
    log_lines+=("  [3/10] Orphan packages")
    local orphans
    orphans=$(pacman -Qdtq 2>/dev/null)
    if [ -n "$orphans" ]; then
        local orphan_count
        orphan_count=$(echo "$orphans" | wc -l)
        if [ "$dry_run" -eq 0 ]; then
            echo "$orphans" | sudo pacman -Rns --noconfirm - >> "$_maintain_log" 2>&1
            log_lines+=("    ✓ Removed $orphan_count orphans")
        else
            log_lines+=("    [DRY-RUN] Would remove $orphan_count orphans")
        fi
    else
        log_lines+=("    ✓ No orphans")
    fi

    # 4. Snap cleanup
    log_lines+=("  [4/10] Snap cleanup")
    if command -v snap &>/dev/null; then
        if [ "$dry_run" -eq 0 ]; then
            sudo snap set system refresh.retain=2 2>/dev/null
            snap list --all 2>/dev/null | awk '/disabled/{print $1, $2}' | while read -r snapname revision; do
                sudo snap remove "$snapname" --revision="$revision" --purge 2>/dev/null || \
                sudo snap remove "$snapname" --purge 2>/dev/null
            done
            log_lines+=("    ✓ Disabled snaps cleaned")
        else
            log_lines+=("    [DRY-RUN] Would clean disabled snap revisions")
        fi
    else
        log_lines+=("    — snap not installed")
    fi

    # 5. Flatpak cleanup
    log_lines+=("  [5/10] Flatpak cleanup")
    if command -v flatpak &>/dev/null; then
        if [ "$dry_run" -eq 0 ]; then
            flatpak uninstall --unused -y >> "$_maintain_log" 2>&1
            log_lines+=("    ✓ Unused runtimes removed")
        else
            log_lines+=("    [DRY-RUN] Would remove unused flatpak runtimes")
        fi
    else
        log_lines+=("    — flatpak not installed")
    fi

    # 6. Journal log cleanup
    log_lines+=("  [6/10] Journal logs")
    if [ "$dry_run" -eq 0 ]; then
        local freed
        freed=$(sudo journalctl --vacuum-time=7d 2>&1 | tail -1)
        sudo journalctl --vacuum-size=100M >> "$_maintain_log" 2>&1
        log_lines+=("    ✓ $freed")
    else
        local journal_size
        journal_size=$(journalctl --disk-usage 2>/dev/null | grep -oP '[\d.]+[KMGT]')
        log_lines+=("    [DRY-RUN] Would vacuum journal (currently $journal_size)")
    fi

    # 7. Old kernel cleanup (Arch uses pacman, kernels are just packages)
    log_lines+=("  [7/10] Old kernels")
    log_lines+=("    — Arch manages kernels via pacman (handled by orphan removal)")

    # 8. Docker cleanup
    log_lines+=("  [8/10] Docker")
    if command -v docker &>/dev/null; then
        if [ "$dry_run" -eq 0 ]; then
            local docker_out
            docker_out=$(docker system prune -f 2>&1 | tail -1)
            log_lines+=("    ✓ $docker_out")
        else
            log_lines+=("    [DRY-RUN] Would prune docker resources")
        fi
    else
        log_lines+=("    — docker not installed")
    fi

    # 9. Steam shader cache cleanup
    log_lines+=("  [9/10] Steam cache")
    if [ -d "$HOME/.steam/steam/steamapps" ]; then
        # shadercache only, as the heading says. compatdata beside it holds
        # the Proton prefixes, where a game keeps its saves unless it uses
        # Steam Cloud — that is not cache, and clearing it loses progress.
        local shader_size
        shader_size=$(du -sh "$HOME/.steam/steam/steamapps/shadercache" 2>/dev/null | cut -f1)
        if [ "$dry_run" -eq 0 ]; then
            rm -rf "$HOME/.steam/steam/steamapps/shadercache/"* 2>/dev/null
            log_lines+=("    ✓ Cleared shader cache (${shader_size:-0})")
        else
            log_lines+=("    [DRY-RUN] Would clear shader cache (${shader_size:-0})")
        fi
    else
        log_lines+=("    — Steam not installed")
    fi

    # 10. Clean temporary files
    log_lines+=("  [10/10] Temporary files")
    if [ "$dry_run" -eq 0 ]; then
        local tmp_count=0
        while IFS= read -r -d '' file; do
            if command -v lsof &>/dev/null; then
                lsof "$file" >/dev/null 2>&1 || { rm -f "$file" 2>/dev/null && tmp_count=$((tmp_count + 1)); }
            elif command -v fuser &>/dev/null; then
                fuser "$file" >/dev/null 2>&1 || { rm -f "$file" 2>/dev/null && tmp_count=$((tmp_count + 1)); }
            else
                rm -f "$file" 2>/dev/null && tmp_count=$((tmp_count + 1))
            fi
        done < <(find /tmp /var/tmp -type f -print0 2>/dev/null)
        log_lines+=("    ✓ Removed $tmp_count temporary files")
    else
        local tmp_total
        tmp_total=$(find /tmp /var/tmp -type f 2>/dev/null | wc -l)
        log_lines+=("    [DRY-RUN] Would clean $tmp_total temporary files")
    fi

    # Report space freed
    log_lines+=("")
    local space_after freed_kb
    space_after=$(df / | awk 'NR==2{print $3}')
    freed_kb=$((space_before - space_after))
    if [ "$freed_kb" -gt 0 ] 2>/dev/null; then
        if command -v numfmt &>/dev/null; then
            log_lines+=("  Disk space freed: $(numfmt --to=iec --suffix=B $((freed_kb * 1024)))")
        else
            log_lines+=("  Disk space freed: ${freed_kb} KB")
        fi
    else
        log_lines+=("  Cleanup complete (no measurable space freed)")
    fi

    printf '%s\n' "${log_lines[@]}" | _yad_pipe "  $mode"
    _notify "$mode complete"
}

# ── Schedule cleanup at boot ──
_maintain_schedule() {
    local script_path
    script_path=$(command -v stoa-maintain 2>/dev/null || echo "$HOME/.local/bin/stoa-maintain")

    # Check if already scheduled (crontab or systemd)
    local already_scheduled=0
    local method=""
    if crontab -l 2>/dev/null | grep -q "stoa-maintain.*--cleanup" \
       || sudo -n crontab -l 2>/dev/null | grep -q "stoa-maintain.*--cleanup"; then
        already_scheduled=1
        method="crontab"
    elif systemctl is-enabled stoa-maintain-cleanup.timer &>/dev/null; then
        already_scheduled=1
        method="systemd timer"
    fi

    if [ "$already_scheduled" -eq 1 ]; then
        local action
        action=$(_yad_select "  Cleanup already scheduled ($method)" \
            "  Remove schedule" \
            "  Keep" \
            "  Back")
        if [[ "$action" == *"Remove"* ]]; then
            if [ "$method" = "crontab" ]; then
                crontab -l 2>/dev/null | grep -v "stoa-maintain" | crontab -
                sudo crontab -l 2>/dev/null | grep -v "stoa-maintain" | sudo crontab -
            else
                sudo systemctl disable stoa-maintain-cleanup.timer 2>/dev/null
                sudo rm -f /etc/systemd/system/stoa-maintain-cleanup.{service,timer} 2>/dev/null
                sudo systemctl daemon-reload 2>/dev/null
            fi
            _notify "Boot cleanup removed ($method)"
        fi
        return
    fi

    _yad_confirm "Schedule system cleanup to run at every boot?" || return

    # systemd first, deliberately: the cleanup runs pacman and journalctl,
    # so it needs root. Scheduled in *this user's* crontab it runs
    # unprivileged with no terminal, every sudo inside fails as a PAM
    # "conversation failed", and pam_faillock counts each one — three is
    # the Arch default and the account is then locked for ten minutes, at
    # the login screen, on the next boot. A root unit has nothing to ask.
    crontab -l 2>/dev/null | grep -q "stoa-maintain" && \
        crontab -l 2>/dev/null | grep -v "stoa-maintain" | crontab -
    if command -v systemctl &>/dev/null; then
        local unit_dir="/etc/systemd/system"
        sudo tee "$unit_dir/stoa-maintain-cleanup.service" >/dev/null <<SVCEOF
[Unit]
Description=Stoa Maintain system cleanup at boot
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash $script_path --cleanup --unattended
SVCEOF
        sudo tee "$unit_dir/stoa-maintain-cleanup.timer" >/dev/null <<TMREOF
[Unit]
Description=Run Stoa Maintain cleanup on boot

[Timer]
OnBootSec=2min

[Install]
WantedBy=timers.target
TMREOF
        sudo systemctl daemon-reload
        sudo systemctl enable stoa-maintain-cleanup.timer
        _notify "Cleanup scheduled at boot (systemd timer)"
    elif command -v crontab &>/dev/null; then
        # No systemd: root's crontab, so the job is privileged already.
        local cron_cmd="@reboot bash $script_path --cleanup --unattended"
        (sudo crontab -l 2>/dev/null | grep -v "stoa-maintain" ; echo "$cron_cmd") \
            | sudo crontab -
        _notify "Cleanup scheduled at boot (root crontab)"
    else
        _notify "Neither systemctl nor crontab found"
    fi
}

# ── Maintenance menu ──
menu_maintain() {
    while true; do
        local choice
        choice=$(_yad_select "  Maintenance" \
            "  Backup Configs" \
            "  Restore / Browse Backups" \
            "  Full Cleanup" \
            "  Cleanup (dry-run)" \
            "  Schedule Cleanup at Boot" \
            "  Back")
        # Anchored: an unanchored *"Back"* also matches "  Backup Configs"
        # and "  Restore / Browse Backups", making both unreachable.
        [ -z "$choice" ] || [[ "$choice" == *Back ]] && return

        case "$choice" in
            *"Backup Configs"*) _maintain_backup ;;
            *"Restore"*)        _maintain_list ;;
            *"dry-run"*)        _maintain_cleanup 1 ;;
            *"Full Cleanup"*)   _maintain_cleanup 0 ;;
            *"Schedule"*)       _maintain_schedule ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════
#   MAIN MENU
# ══════════════════════════════════════════════════════════════

main_menu() {
    while true; do
        local choice
        choice=$(_yad_select "  Settings" \
            "  Display" \
            "  Audio" \
            "  Equalizer" \
            "  Night Light" \
            "  Keyboard" \
            "  Mouse & Touchpad" \
            "  Network" \
            "  VPN" \
            "  Firewall" \
            "  Bluetooth" \
            "  Hardware" \
            "  Disks & Storage" \
            "  Printers & Scanners" \
            "  Cloud Drive" \
            "  Wallpaper" \
            "  Theme" \
            "  Power Management" \
            "  Date & Time" \
            "  Accessibility" \
            "  Screensaver" \
            "  System Health" \
            "  Maintenance" \
            "  Stoa Config")
        [ -z "$choice" ] && exit 0

        case "$choice" in
            *Display*)      menu_display ;;
            *Audio*)        menu_audio ;;
            *Equalizer*)    menu_equalizer ;;
            *"Night Light"*) menu_nightlight ;;
            *Keyboard*)     menu_keyboard ;;
            *"Mouse & Touchpad"*) menu_mouse ;;
            *Network*)      menu_network ;;
            *VPN*)          menu_vpn ;;
            *Firewall*)     menu_firewall ;;
            *Bluetooth*)    menu_bluetooth ;;
            *Hardware*)     menu_hardware ;;
            *"Disks & Storage"*) menu_disks ;;
            *"Printers & Scanners"*) menu_printers ;;
            *"Cloud Drive"*) stoa-drive & disown; exit 0 ;;
            *Wallpaper*)    menu_wallpaper ;;
            *Theme*)        menu_theme ;;
            *"Power Management"*) menu_power_mgmt ;;
            *"Date & Time"*) menu_datetime ;;
            *Accessibility*) menu_accessibility ;;
            *Screensaver*)  menu_screensaver ;;
            *"System Health"*) menu_health ;;
            *Maintenance*)  menu_maintain ;;
            *Stoa*)         menu_stoa ;;
        esac
    done
}

main_menu
