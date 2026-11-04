# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — yad helpers                                    ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Sourced by stoa-settings, stoa-store (core.sh), stoa-clipboard, stoa-paste,
# stoa-drive and stoa-health. Two jobs:
#
#   1. Size list / text windows from their content, so a 4-row menu is a small
#      dialog and a long list is a taller one (capped, then it scrolls).
#      The compositors float and centre every yad window (window rules in
#      config/niri/config.kdl and config/hypr/hyprland.lua); the size we pass
#      here is what those floating windows open at.
#
#   2. Keep Pango markup out of list cells. yad --list renders cell text as
#      markup; a bare "&" or "<" is invalid, so GTK keeps the previous row's
#      text in that cell (the label looks duplicated while the tooltip and the
#      click still use the real value). Escape on the way in, unescape on the
#      way out, so callers keep matching on the original label.
#
# Tunables (env): STOA_YAD_CHAR_W, STOA_YAD_ROW_H, STOA_YAD_MAX_W,
# STOA_YAD_MAX_H — pixels, for the list font.

_yad_esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

_yad_unesc() {
    local s="$1"
    # The & in the replacement is quoted: bash 5.2 expands a bare & to the match.
    s=${s//&lt;/"<"}; s=${s//&gt;/">"}; s=${s//&amp;/"&"}
    printf '%s\n' "$s"
}

# _yad_geom TEXT TITLE CHAR_W ROW_H PAD_W PAD_H MIN_W MIN_H MAX_W MAX_H
# Prints "<width> <height>": widest line / row count of TEXT, scaled to pixels,
# plus padding for the window chrome, clamped to [min, max].
_yad_geom() {
    local text="$1" title="$2" cw="$3" rh="$4" pw="$5" ph="$6"
    local minw="$7" minh="$8" maxw="$9" maxh="${10}"
    local rows cols w h
    rows=$(printf '%s\n' "$text" | wc -l)
    cols=$(printf '%s\n' "$text" | wc -L)
    [ "${#title}" -gt "$cols" ] && cols=${#title}
    w=$(( cols * cw + pw ))
    h=$(( rows * rh + ph ))
    [ "$w" -lt "$minw" ] && w=$minw
    [ "$w" -gt "$maxw" ] && w=$maxw
    [ "$h" -lt "$minh" ] && h=$minh
    [ "$h" -gt "$maxh" ] && h=$maxh
    echo "$w $h"
}

# stoa_yad_list TITLE   — rows on stdin, picked row on stdout (yad's exit code).
stoa_yad_list() {
    local title="$1" input out rc w h
    input=$(cat)
    read -r w h < <(_yad_geom "$input" "$title" \
        "${STOA_YAD_CHAR_W:-9}" "${STOA_YAD_ROW_H:-27}" 90 110 \
        320 180 "${STOA_YAD_MAX_W:-900}" "${STOA_YAD_MAX_H:-720}")
    out=$(printf '%s\n' "$input" | _yad_esc \
        | yad --list --title="$title" --column="Option" --no-headers \
              --width="$w" --height="$h" --center --separator='')
    rc=$?
    _yad_unesc "$out"
    return $rc
}

# stoa_yad_info TITLE   — text on stdin, shown read-only with a Close button.
stoa_yad_info() {
    local title="$1" input w h
    input=$(cat)
    read -r w h < <(_yad_geom "$input" "$title" \
        9 22 80 120 \
        360 200 "${STOA_YAD_MAX_W:-1000}" "${STOA_YAD_MAX_H:-760}")
    printf '%s\n' "$input" \
        | yad --text-info --title="$title" --fontname="monospace 11" \
              --width="$w" --height="$h" --center --button="Close:0"
}
