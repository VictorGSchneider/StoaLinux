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

menu_network() {
    while true; do
        local status
        status=$(_wifi_status)
        local wifi_state
        wifi_state=$(nmcli radio wifi 2>/dev/null)

        local choice
        choice=$(_rofi_select "  Network ($status)" \
            "  Connect to Wi-Fi" \
            "  Disconnect" \
            "  Forget network" \
            "  Toggle Wi-Fi ($wifi_state)" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *Connect*)    _wifi_connect ;;
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
            "  Disconnect device" \
            "  Toggle Bluetooth ($status)" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *Scan*)       _bt_scan_connect ;;
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
                alacritty -e sudo stoa-face setup &
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
                alacritty -e stoa-fetch &
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
            "  Bluetooth" \
            "  Cloud Drive" \
            "  Wallpaper" \
            "  Theme" \
            "  App Store" \
            "  Lock Screen" \
            "  Stoa Config" \
            "  Power")
        [ -z "$choice" ] && exit 0

        case "$choice" in
            *Display*)      menu_display ;;
            *Audio*)        menu_audio ;;
            *Network*)      menu_network ;;
            *VPN*)          menu_vpn ;;
            *Bluetooth*)    menu_bluetooth ;;
            *"Cloud Drive"*) stoa-drive & disown; exit 0 ;;
            *Wallpaper*)    menu_wallpaper ;;
            *Theme*)        menu_theme ;;
            *"App Store"*)  stoa-store & disown; exit 0 ;;
            *Lock*)         menu_lockscreen ;;
            *Stoa*)         menu_stoa ;;
            *Power*)        menu_power ;;
        esac
    done
}

main_menu
