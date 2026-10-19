#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — stoa-wm (compositor-neutral control)           ║
# ║  "Choose not to be harmed — and you won't feel harmed."      ║
# ╚══════════════════════════════════════════════════════════════╝
#
# One command line for the things Stoa needs from the compositor, whether
# the session is Hyprland or niri. Keybinds, gestures and scripts call this
# instead of hyprctl / niri msg.
#
#   stoa-wm name                      hyprland | niri
#   stoa-wm version
#   stoa-wm set <hyprland|niri>       remember the choice for the next login
#   stoa-wm outputs                   one JSON object per output
#   stoa-wm internal | external | focused-output
#   stoa-wm extend <out> [ref]        place <out> to the right of [ref]
#   stoa-wm mirror <out> <src>
#   stoa-wm disable <out>
#   stoa-wm geom                      focused window as "X,Y WxH"
#   stoa-wm action <name>             close fullscreen float workspace-next …
#   stoa-wm cursor <theme> [size]
#   stoa-wm reload | exit | lock
#   stoa-wm start-command [wm]

_STOA_LIB="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib"
if [ ! -r "$_STOA_LIB/stoa-wm.sh" ]; then
    echo "stoa-wm: missing $_STOA_LIB/stoa-wm.sh" >&2
    exit 1
fi
# shellcheck source=lib/stoa-wm.sh
source "$_STOA_LIB/stoa-wm.sh"

_usage() {
    sed -n '/^#   stoa-wm name/,/^#   stoa-wm start-command/p' "${BASH_SOURCE[0]}" | sed 's/^#//'
}

cmd="${1:-}"
[ $# -gt 0 ] && shift

case "$cmd" in
    name)          stoa_wm_name ;;
    version)       stoa_wm_version ;;
    set)
        case "${1:-}" in
            hyprland|niri)
                mkdir -p "$(dirname "$STOA_WM_CHOICE_FILE")"
                echo "$1" > "$STOA_WM_CHOICE_FILE"
                ;;
            *) echo "usage: stoa-wm set <hyprland|niri>" >&2; exit 2 ;;
        esac
        ;;
    outputs)       stoa_wm_outputs ;;
    internal)      stoa_wm_internal_output ;;
    external)      stoa_wm_external_output ;;
    focused-output) stoa_wm_focused_output ;;
    extend)        stoa_wm_output_extend "${1:?output}" "${2:-}" ;;
    mirror)        stoa_wm_output_mirror "${1:?output}" "${2:?source}" ;;
    disable)       stoa_wm_output_disable "${1:?output}" ;;
    geom)          stoa_wm_active_window_geom ;;
    action)
        stoa_wm_action "${1:?action}"
        rc=$?
        case "$rc" in
            2) echo "stoa-wm: unknown action '$1'" >&2 ;;
            3) echo "stoa-wm: '$1' is not available on $(stoa_wm_display_name)" >&2 ;;
        esac
        exit "$rc"
        ;;
    cursor)        stoa_wm_set_cursor "${1:?theme}" "${2:-24}" ;;
    reload)        stoa_wm_reload ;;
    exit)          stoa_wm_exit ;;
    lock)          stoa_wm_lock ;;
    start-command) stoa_wm_start_command "${1:-}" ;;
    ""|-h|--help|help) _usage ;;
    *) echo "stoa-wm: unknown command '$cmd'" >&2; _usage >&2; exit 2 ;;
esac
