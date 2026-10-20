#!/bin/bash
# Behavioural test for scripts/lib/stoa-wm.sh, the Hyprland/niri abstraction.
#
# Neither compositor runs in CI, so both are stubbed: fake `hyprctl` and
# `niri` executables answer with the JSON the real ones print (shapes taken
# from the niri-ipc crate and `hyprctl -j`), and log every command they are
# given. Properties checked:
#
#   W1  detection: $STOA_WM beats the running session, which beats the
#       recorded choice, which beats whatever binary is installed
#   W2  `outputs` normalises both compositors to the same shape (logical
#       size, not pixels) and drops a disabled output
#   W3  internal / external pick the laptop panel and the other one, and
#       find an external output that niri currently has switched off
#   W4  extend places the external output flush right of the internal one:
#       a Hyprland keyword, or `niri msg output … position set <width> 0`
#   W5  the focused window's geometry comes out in grim/slurp syntax on both
#   W6  actions map to the right command, an unknown one returns 2, and
#       `minimize` returns 3 on niri (no such thing there)
#   W7  mirror is refused on niri without wl-mirror
#   W8  shell/stoa-env.sh's XDG_CURRENT_DESKTOP fallback follows the
#       recorded choice / installed compositor, and never overrides a session

cd "$(dirname "$0")/.." || exit 1

LIB="$PWD/scripts/lib/stoa-wm.sh"
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

BIN="$TMP/bin"; LOG="$TMP/calls.log"
mkdir -p "$BIN" "$TMP/home"
: > "$LOG"

# ── Stubs ──
cat > "$BIN/hyprctl" <<'STUB'
#!/bin/bash
echo "hyprctl $*" >> "$STUB_LOG"
case "$1 $2 $3" in
    "monitors all -j") cat <<'JSON'
[{"name":"eDP-1","x":0,"y":0,"width":2880,"height":1800,"scale":1.5,"focused":true,"disabled":false},
 {"name":"HDMI-A-1","x":1920,"y":0,"width":1920,"height":1080,"scale":1.0,"focused":false,"disabled":false},
 {"name":"DP-2","x":0,"y":0,"width":1920,"height":1080,"scale":1.0,"focused":false,"disabled":true}]
JSON
    ;;
esac
case "$1 $2" in
    "activewindow -j") echo '{"at":[100,50],"size":[800,600]}' ;;
    "version -j") echo '{"tag":"v0.55.1"}' ;;
esac
STUB
cat > "$BIN/niri" <<'STUB'
#!/bin/bash
echo "niri $*" >> "$STUB_LOG"
if [ "$1" = "--version" ]; then echo "niri 25.08"; exit 0; fi
[ "$1 $2" = "msg --json" ] || exit 0
case "$3" in
    outputs) cat <<'JSON'
{"eDP-1":{"name":"eDP-1","logical":{"x":0,"y":0,"width":1920,"height":1200,"scale":1.5,"transform":"Normal"}},
 "HDMI-A-1":{"name":"HDMI-A-1","logical":null}}
JSON
    ;;
    focused-output) echo '{"name":"eDP-1","logical":{"x":0,"y":0,"width":1920,"height":1200,"scale":1.5}}' ;;
    focused-window) echo '{"id":1,"layout":{"tile_size":[960.0,1188.0],"tile_pos_in_workspace_view":[6.0,6.0],"window_size":[956,1184],"window_offset_in_tile":[2.0,2.0]}}' ;;
esac
STUB
chmod +x "$BIN/hyprctl" "$BIN/niri"

# Run a snippet with the library loaded, in a clean environment so the
# machine running the test cannot leak its own session into the result.
_wm() {
    env -i PATH="$BIN:/usr/bin:/bin" HOME="$TMP/home" STUB_LOG="$LOG" "$@" \
        bash -c "source '$LIB'; $SNIPPET"
}
FAILS=0
_check() { # <name> <want> <got>
    if [ "$2" = "$3" ]; then return 0; fi
    echo "FAIL $1"; echo "   want: $2"; echo "   got:  $3"; FAILS=$((FAILS + 1))
}

# ── W1 detection ──
SNIPPET='stoa_wm_name'
_check "W1 override"            "niri"     "$(_wm STOA_WM=niri HYPRLAND_INSTANCE_SIGNATURE=x)"
_check "W1 niri session"        "niri"     "$(_wm NIRI_SOCKET=/s)"
_check "W1 hyprland session"    "hyprland" "$(_wm HYPRLAND_INSTANCE_SIGNATURE=x)"
_check "W1 XDG_CURRENT_DESKTOP" "niri"     "$(_wm XDG_CURRENT_DESKTOP=niri)"
mkdir -p "$TMP/home/.config/stoa"; echo niri > "$TMP/home/.config/stoa/wm"
_check "W1 recorded choice"     "niri"     "$(_wm)"
_check "W1 session beats file"  "hyprland" "$(_wm HYPRLAND_INSTANCE_SIGNATURE=x)"
rm -f "$TMP/home/.config/stoa/wm"
_check "W1 installed binary"    "niri"     "$(_wm)"   # only the niri stub is named niri; hyprctl is not Hyprland

# ── W2 outputs ──
SNIPPET='stoa_wm_outputs | jq -c "[.name,.w,.h,.focused]"'
_check "W2 hyprland outputs" '["eDP-1",1920,1200,true]
["HDMI-A-1",1920,1080,false]' "$(_wm STOA_WM=hyprland)"
_check "W2 niri outputs" '["eDP-1",1920,1200,true]' "$(_wm STOA_WM=niri)"

# ── W3 internal / external ──
SNIPPET='echo "$(stoa_wm_internal_output) $(stoa_wm_external_output)"'
_check "W3 hyprland" "eDP-1 HDMI-A-1" "$(_wm STOA_WM=hyprland)"
_check "W3 niri (external is off)" "eDP-1 HDMI-A-1" "$(_wm STOA_WM=niri)"

# ── W4 extend ──
: > "$LOG"; SNIPPET='stoa_wm_output_extend HDMI-A-1 eDP-1'
_wm STOA_WM=hyprland >/dev/null
_check "W4 hyprland extend" "hyprctl keyword monitor HDMI-A-1,preferred,auto-right,1" "$(grep keyword "$LOG")"
: > "$LOG"; _wm STOA_WM=niri >/dev/null
_check "W4 niri extend" "niri msg output HDMI-A-1 position set 1920 0" "$(grep 'position' "$LOG")"

# ── W5 window geometry ──
SNIPPET='stoa_wm_active_window_geom'
_check "W5 hyprland geom" "100,50 800x600" "$(_wm STOA_WM=hyprland)"
_check "W5 niri geom"     "6,6 960x1188"   "$(_wm STOA_WM=niri)"

# ── W6 actions ──
: > "$LOG"; SNIPPET='stoa_wm_action close'
_wm STOA_WM=hyprland >/dev/null; _wm STOA_WM=niri >/dev/null
_check "W6 close" "hyprctl dispatch killactive
niri msg action close-window" "$(cat "$LOG")"
SNIPPET='stoa_wm_action nonsense; echo $?'
_check "W6 unknown action"      "2" "$(_wm STOA_WM=niri | tail -n1)"
SNIPPET='stoa_wm_action minimize; echo $?'
_check "W6 niri has no minimize" "3" "$(_wm STOA_WM=niri | tail -n1)"

# ── W7 mirror ──
SNIPPET='stoa_wm_can_mirror && echo yes || echo no'
_check "W7 niri without wl-mirror" "no"  "$(_wm STOA_WM=niri)"
_check "W7 hyprland mirrors"       "yes" "$(_wm STOA_WM=hyprland)"

# ── W8 stoa-env.sh fallback ──
_env() { # <env assignments...>: XDG_CURRENT_DESKTOP after sourcing stoa-env.sh
    env -i PATH="$BIN:/usr/bin:/bin" HOME="$TMP/home" "$@" \
        bash -c "source '$PWD/shell/stoa-env.sh'; printf '%s' \"\$XDG_CURRENT_DESKTOP\""
}
_check "W8 session value kept"   "Hyprland" "$(_env XDG_CURRENT_DESKTOP=Hyprland)"
_check "W8 only niri installed"  "niri"     "$(_env)"
echo hyprland > "$TMP/home/.config/stoa/wm"
_check "W8 recorded hyprland"    "Hyprland" "$(_env)"
echo niri > "$TMP/home/.config/stoa/wm"
_check "W8 recorded niri"        "niri"     "$(_env)"
printf '#!/bin/sh\n' > "$BIN/Hyprland"; chmod +x "$BIN/Hyprland"
_check "W8 file beats binaries"  "niri"     "$(_env)"
rm -f "$TMP/home/.config/stoa/wm"
_check "W8 both installed"       "Hyprland" "$(_env)"
rm -f "$BIN/Hyprland"

[ "$FAILS" -eq 0 ] || { echo "$FAILS check(s) failed"; exit 1; }
echo "stoa-wm: all checks passed"
