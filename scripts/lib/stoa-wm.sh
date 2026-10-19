# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Compositor abstraction                         ║
# ║  "Choose not to be harmed — and you won't feel harmed."      ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Sourced by stoa-wm, stoa-display, stoa-capture, stoa-doctor, stoa-settings
# and stoa-store. Stoa supports two Wayland compositors, Hyprland and niri;
# anything that has to talk to "the compositor" goes through the stoa_wm_*
# functions below instead of calling hyprctl / niri msg directly, so a script
# is written once and works in both sessions.
#
# Which compositor is "the" compositor, in order:
#   1. $STOA_WM            explicit override (hyprland | niri)
#   2. the running session  $NIRI_SOCKET / $HYPRLAND_INSTANCE_SIGNATURE /
#                           $XDG_CURRENT_DESKTOP
#   3. ~/.config/stoa/wm    the choice post-install.sh / install.sh recorded
#   4. whichever binary is installed (Hyprland wins when both are)
#
# Every function degrades to "do nothing, return non-zero" when the
# compositor cannot do the thing (niri has no output mirroring, Hyprland has
# no external-output "on" toggle that survives a hotplug…) — callers decide
# whether that deserves a notification.

STOA_WM_CHOICE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/wm"

# Name of the compositor: "hyprland", "niri" or "" when none is detectable.
stoa_wm_name() {
    local wm
    wm=$(printf '%s' "${STOA_WM:-}" | tr '[:upper:]' '[:lower:]')
    case "$wm" in hyprland|niri) echo "$wm"; return 0 ;; esac

    if [ -n "${NIRI_SOCKET:-}" ]; then echo niri; return 0; fi
    if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then echo hyprland; return 0; fi
    case "$(printf '%s' "${XDG_CURRENT_DESKTOP:-}" | tr '[:upper:]' '[:lower:]')" in
        *niri*)     echo niri; return 0 ;;
        *hyprland*) echo hyprland; return 0 ;;
    esac

    if [ -r "$STOA_WM_CHOICE_FILE" ]; then
        wm=$(head -n1 "$STOA_WM_CHOICE_FILE" 2>/dev/null | tr -d '[:space:]')
        case "$wm" in hyprland|niri) echo "$wm"; return 0 ;; esac
    fi

    if command -v Hyprland >/dev/null 2>&1; then echo hyprland; return 0; fi
    if command -v niri >/dev/null 2>&1; then echo niri; return 0; fi
    return 1
}

# True when $1 (hyprland|niri) is the compositor.
stoa_wm_is() {
    [ "$(stoa_wm_name 2>/dev/null)" = "$1" ]
}

# True only when the *running* session is Hyprland and hyprctl can reach it.
# Use this instead of `command -v hyprctl` before a live `hyprctl keyword`:
# a machine with both compositors installed still has hyprctl on PATH while
# sitting in a niri session, where it can only fail.
stoa_wm_hypr_live() {
    command -v hyprctl >/dev/null 2>&1 \
        && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] \
        && stoa_wm_is hyprland
}

# True when the running session is niri and `niri msg` can reach it.
stoa_wm_niri_live() {
    command -v niri >/dev/null 2>&1 \
        && [ -n "${NIRI_SOCKET:-}" ] \
        && stoa_wm_is niri
}

# Human-readable name for banners.
stoa_wm_display_name() {
    case "$(stoa_wm_name 2>/dev/null)" in
        hyprland) echo "Hyprland" ;;
        niri)     echo "niri" ;;
        *)        echo "unknown compositor" ;;
    esac
}

# Directory holding the compositor's config.
stoa_wm_config_dir() {
    case "$(stoa_wm_name 2>/dev/null)" in
        hyprland) echo "${XDG_CONFIG_HOME:-$HOME/.config}/hypr" ;;
        niri)     echo "${XDG_CONFIG_HOME:-$HOME/.config}/niri" ;;
        *)        return 1 ;;
    esac
}

# Path of the compositor's main config file.
stoa_wm_config_file() {
    local dir
    dir=$(stoa_wm_config_dir) || return 1
    case "$(stoa_wm_name)" in
        hyprland) echo "$dir/hyprland.lua" ;;
        niri)     echo "$dir/config.kdl" ;;
    esac
}

# Compositor version, e.g. "0.55.1" / "25.08". Empty when unknown.
stoa_wm_version() {
    case "$(stoa_wm_name 2>/dev/null)" in
        hyprland)
            command -v hyprctl >/dev/null 2>&1 || return 1
            hyprctl version -j 2>/dev/null | jq -r '.tag // .version // empty' 2>/dev/null | head -n1
            ;;
        niri)
            command -v niri >/dev/null 2>&1 || return 1
            niri --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1
            ;;
        *) return 1 ;;
    esac
}

# ── Outputs ──
#
# Normalised output list: one JSON object per line,
#   {"name":"eDP-1","x":0,"y":0,"w":1920,"h":1080,"scale":1,"focused":true}
# w/h are *logical* pixels (what the compositor lays out), x/y the position
# in the global coordinate space. Disabled outputs are omitted.
stoa_wm_outputs() {
    case "$(stoa_wm_name 2>/dev/null)" in
        hyprland)
            hyprctl monitors all -j 2>/dev/null | jq -c '
                .[] | select((.disabled // false) | not) | {
                    name: .name, x: .x, y: .y,
                    w: ((.width  / (.scale // 1)) | floor),
                    h: ((.height / (.scale // 1)) | floor),
                    scale: (.scale // 1),
                    focused: (.focused // false)
                }'
            ;;
        niri)
            local focused
            focused=$(niri msg --json focused-output 2>/dev/null | jq -r '.name // empty' 2>/dev/null)
            niri msg --json outputs 2>/dev/null | jq -c --arg f "$focused" '
                to_entries[] | .value | select(.logical != null) | {
                    name: .name, x: .logical.x, y: .logical.y,
                    w: .logical.width, h: .logical.height,
                    scale: .logical.scale,
                    focused: (.name == $f)
                }'
            ;;
        *) return 1 ;;
    esac
}

# Names only, one per line. Includes outputs that are currently off on niri
# (so "turn the external one back on" can find it).
stoa_wm_output_names() {
    case "$(stoa_wm_name 2>/dev/null)" in
        hyprland) hyprctl monitors all -j 2>/dev/null | jq -r '.[].name' ;;
        niri)     niri msg --json outputs 2>/dev/null | jq -r 'to_entries[] | .value.name' ;;
        *)        return 1 ;;
    esac
}

# First eDP/LVDS panel (the laptop screen).
stoa_wm_internal_output() {
    stoa_wm_output_names 2>/dev/null | grep -iE '^(eDP|LVDS)' | head -n1
}

# First output that is not the laptop panel.
stoa_wm_external_output() {
    stoa_wm_output_names 2>/dev/null | grep -ivE '^(eDP|LVDS)' | head -n1
}

# Name of the output that has focus (falls back to the first one).
stoa_wm_focused_output() {
    local name
    name=$(stoa_wm_outputs 2>/dev/null | jq -r 'select(.focused) | .name' | head -n1)
    [ -n "$name" ] || name=$(stoa_wm_outputs 2>/dev/null | jq -r '.name' | head -n1)
    [ -n "$name" ] && echo "$name"
}

# Put output $1 to the right of $2 (default: the internal panel).
stoa_wm_output_extend() {
    local ext="$1" ref="${2:-}"
    case "$(stoa_wm_name 2>/dev/null)" in
        hyprland)
            hyprctl keyword monitor "${ext},preferred,auto-right,1" >/dev/null
            ;;
        niri)
            # Re-enable it, then place it flush right of $ref. Positions are
            # logical pixels, so use the reference's logical width.
            niri msg output "$ext" on >/dev/null 2>&1 || true
            local x
            [ -n "$ref" ] && x=$(stoa_wm_outputs | jq -r --arg n "$ref" 'select(.name==$n) | .x + .w' | head -n1)
            if [ -n "${x:-}" ]; then
                niri msg output "$ext" position set "$x" 0 >/dev/null 2>&1 || \
                    niri msg output "$ext" position auto >/dev/null 2>&1 || true
            else
                niri msg output "$ext" position auto >/dev/null 2>&1 || true
            fi
            ;;
        *) return 1 ;;
    esac
}

# Can this compositor mirror one output onto another?
stoa_wm_can_mirror() {
    case "$(stoa_wm_name 2>/dev/null)" in
        hyprland) return 0 ;;
        niri)     command -v wl-mirror >/dev/null 2>&1 ;;
        *)        return 1 ;;
    esac
}

# Make output $1 show the same picture as output $2.
# niri has no native mirroring: wl-mirror fullscreens a copy of $2 on $1.
stoa_wm_output_mirror() {
    local ext="$1" src="$2"
    case "$(stoa_wm_name 2>/dev/null)" in
        hyprland)
            hyprctl keyword monitor "${ext},preferred,auto,1,mirror,${src}" >/dev/null
            ;;
        niri)
            command -v wl-mirror >/dev/null 2>&1 || return 1
            niri msg output "$ext" on >/dev/null 2>&1 || true
            stoa_wm_mirror_stop
            nohup wl-mirror --fullscreen --fullscreen-output "$ext" "$src" \
                >/dev/null 2>&1 &
            ;;
        *) return 1 ;;
    esac
}

# Stop any wl-mirror started by stoa_wm_output_mirror (niri only).
stoa_wm_mirror_stop() {
    pkill -x wl-mirror 2>/dev/null || true
}

# Turn output $1 off.
stoa_wm_output_disable() {
    local ext="$1"
    case "$(stoa_wm_name 2>/dev/null)" in
        hyprland) hyprctl keyword monitor "${ext},disable" >/dev/null ;;
        niri)     stoa_wm_mirror_stop; niri msg output "$ext" off >/dev/null 2>&1 ;;
        *)        return 1 ;;
    esac
}

# ── Windows ──

# Geometry of the focused window as "X,Y WxH" (slurp/grim syntax) in the
# global logical coordinate space. Empty (and non-zero) when there is none or
# the compositor does not report enough to place it.
stoa_wm_active_window_geom() {
    case "$(stoa_wm_name 2>/dev/null)" in
        hyprland)
            local json
            json=$(hyprctl activewindow -j 2>/dev/null) || return 1
            [ -n "$json" ] || return 1
            echo "$json" | jq -er \
                'select(.at != null) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"' 2>/dev/null
            ;;
        niri)
            local win out
            win=$(niri msg --json focused-window 2>/dev/null) || return 1
            [ -n "$win" ] && [ "$win" != "null" ] || return 1
            out=$(stoa_wm_outputs | jq -c 'select(.focused)' | head -n1)
            [ -n "$out" ] || return 1
            # Visual tile = window + border. Position is relative to the
            # workspace view, which is the focused output's origin.
            jq -nr --argjson w "$win" --argjson o "$out" '
                ($w.layout.tile_pos_in_workspace_view // null) as $p
                | if $p == null then empty
                  else "\(($o.x + $p[0]) | floor),\(($o.y + $p[1]) | floor) \(($w.layout.tile_size[0]) | floor)x\(($w.layout.tile_size[1]) | floor)"
                  end' 2>/dev/null
            ;;
        *) return 1 ;;
    esac
}

# Normalised window actions, so keybinds / gestures / scripts say what they
# mean once. Names:
#   workspace-next workspace-prev
#   close fullscreen float
#   move-left move-right move-up move-down
#   focus-next focus-prev
#   minimize          (Hyprland: special workspace; niri: no such thing)
#   overview          (Alt+Tab-style window overview)
stoa_wm_action() {
    local act="${1:-}"
    case "$(stoa_wm_name 2>/dev/null)" in
        hyprland)
            case "$act" in
                workspace-next) hyprctl dispatch workspace e+1 ;;
                workspace-prev) hyprctl dispatch workspace e-1 ;;
                close)          hyprctl dispatch killactive ;;
                fullscreen)     hyprctl dispatch fullscreen ;;
                float)          hyprctl dispatch togglefloating ;;
                move-left)      hyprctl dispatch movewindow l ;;
                move-right)     hyprctl dispatch movewindow r ;;
                move-up)        hyprctl dispatch movewindow u ;;
                move-down)      hyprctl dispatch movewindow d ;;
                focus-next)     hyprctl dispatch cyclenext ;;
                focus-prev)     hyprctl dispatch cyclenext prev ;;
                minimize)       hyprctl dispatch movetospecialworkspace minimize ;;
                overview)
                    hyprswitch gui --mod-key ALT --key Tab --close mod-key-release \
                        --max-switch-offset 9 --hide-active-window-border && hyprswitch dispatch
                    ;;
                *) return 2 ;;
            esac
            ;;
        niri)
            case "$act" in
                workspace-next) niri msg action focus-workspace-down ;;
                workspace-prev) niri msg action focus-workspace-up ;;
                close)          niri msg action close-window ;;
                fullscreen)     niri msg action fullscreen-window ;;
                float)          niri msg action toggle-window-floating ;;
                move-left)      niri msg action move-column-left ;;
                move-right)     niri msg action move-column-right ;;
                move-up)        niri msg action move-window-up ;;
                move-down)      niri msg action move-window-down ;;
                focus-next)     niri msg action focus-column-right ;;
                focus-prev)     niri msg action focus-column-left ;;
                overview)       niri msg action toggle-overview ;;
                minimize)       return 3 ;;
                *)              return 2 ;;
            esac
            ;;
        *) return 1 ;;
    esac
}

# ── Session ──

# Apply a cursor theme + size to the running session.
stoa_wm_set_cursor() {
    local theme="$1" size="${2:-24}"
    case "$(stoa_wm_name 2>/dev/null)" in
        hyprland)
            stoa_wm_hypr_live && hyprctl setcursor "$theme" "$size" >/dev/null 2>&1
            ;;
        niri)
            # niri takes the cursor from its config (`cursor { … }`), which it
            # reloads on save. Rewrite the two lines in place.
            local cfg
            cfg=$(stoa_wm_config_file) || return 1
            [ -f "$cfg" ] || return 1
            sed -i --follow-symlinks -E \
                -e "s|^([[:space:]]*xcursor-theme[[:space:]]+).*|\1\"${theme}\"|" \
                -e "s|^([[:space:]]*xcursor-size[[:space:]]+).*|\1${size}|" "$cfg"
            ;;
        *) return 1 ;;
    esac
}

# Re-read the compositor config. niri watches its config file, so that one
# is a no-op that still succeeds.
stoa_wm_reload() {
    case "$(stoa_wm_name 2>/dev/null)" in
        hyprland) stoa_wm_hypr_live && hyprctl reload >/dev/null 2>&1 ;;
        niri)     return 0 ;;
        *)        return 1 ;;
    esac
}

# Leave the session.
stoa_wm_exit() {
    case "$(stoa_wm_name 2>/dev/null)" in
        hyprland) hyprctl dispatch exit ;;
        niri)     niri msg action quit --skip-confirmation ;;
        *)        return 1 ;;
    esac
}

# Lock the screen. Noctalia owns the lock screen under both compositors.
stoa_wm_lock() {
    command -v noctalia >/dev/null 2>&1 && noctalia msg lock
}

# Command line that starts the compositor from a TTY.
stoa_wm_start_command() {
    case "${1:-$(stoa_wm_name 2>/dev/null)}" in
        hyprland) echo "start-hyprland" ;;
        niri)     echo "niri-session" ;;
        *)        return 1 ;;
    esac
}
