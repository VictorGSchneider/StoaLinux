# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — compositor autostart on tty1                  ║
# ║  "What stands in the way becomes the way." — Marcus Aurelius║
# ║                                                              ║
# ║  Sourced from ~/.zprofile / ~/.bash_profile. Combined with   ║
# ║  systemd autologin on tty1 (see setup/enable-stoa-greeter.sh)║
# ║  this boots straight into the chosen compositor: Hyprland,   ║
# ║  whose first exec-once is hyprlock, or niri, where Noctalia  ║
# ║  puts up the lock screen — so the lock page IS the login.    ║
# ║                                                              ║
# ║  (The file keeps its old name: existing ~/.zprofile blocks   ║
# ║  source it by path.)                                         ║
# ╚══════════════════════════════════════════════════════════════╝

# Which compositor: ~/.config/stoa/wm (written by post-install.sh or
# `stoa-wm set <hyprland|niri>`), else whichever is installed.
if [ -z "$WAYLAND_DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    _stoa_wm_pick=""
    [ -r "${XDG_CONFIG_HOME:-$HOME/.config}/stoa/wm" ] && \
        _stoa_wm_pick=$(head -n1 "${XDG_CONFIG_HOME:-$HOME/.config}/stoa/wm" | tr -d '[:space:]')

    case "$_stoa_wm_pick" in
        niri)     command -v niri-session >/dev/null 2>&1 || _stoa_wm_pick="" ;;
        hyprland) command -v Hyprland >/dev/null 2>&1 || _stoa_wm_pick="" ;;
        *)        _stoa_wm_pick="" ;;
    esac
    if [ -z "$_stoa_wm_pick" ]; then
        if command -v Hyprland >/dev/null 2>&1; then _stoa_wm_pick="hyprland"
        elif command -v niri-session >/dev/null 2>&1; then _stoa_wm_pick="niri"
        fi
    fi

    case "$_stoa_wm_pick" in
        hyprland) unset _stoa_wm_pick; exec start-hyprland ;;
        niri)     unset _stoa_wm_pick; exec niri-session ;;
    esac
    unset _stoa_wm_pick
fi
