#!/bin/bash
# config/hypr/hyprland.lua must pass Hyprland's own `--verify-config`.
#
# The data group only proves the file parses (luac -p). Hyprland then runs
# it, and a call that fails at run time — a require() for a module that is
# not there, a dispatcher that was renamed — is a config error the parser
# never sees. The shipped file ended with
#
#     require("noctalia").apply_theme()
#
# appended by Noctalia's colour-template feature on one machine and committed
# by a sync; ~/.config/hypr/noctalia.lua exists nowhere else, and Hyprland
# answers "module 'noctalia' not found" on every start. stoa-doctor runs
# `niri validate` for the niri config; this is the same check for the other
# compositor.
#
#   H1  Hyprland --verify-config accepts the shipped config
#
# Needs the Hyprland binary and a non-root user (Hyprland refuses to start as
# root), so it runs on a machine that has Hyprland installed and skips
# elsewhere, CI included. --verify-config only parses: no session is started.

cd "$(dirname "$0")/.." || exit 1
command -v Hyprland >/dev/null || { echo "Hyprland missing — skipped (runs where it is installed)"; exit 0; }
[ "$(id -u)" -ne 0 ] || { echo "running as root — skipped (Hyprland refuses root)"; exit 0; }
Hyprland --help 2>&1 | grep -q -- '--verify-config' \
    || { echo "this Hyprland has no --verify-config — skipped"; exit 0; }

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
FAILS=0
_check() { # <name> <expected> <actual>
    if [ "$2" = "$3" ]; then printf '  ✓ %s\n' "$1"
    else printf '  ✗ %s: expected [%s], got [%s]\n' "$1" "$2" "$3"; FAILS=$((FAILS + 1)); fi
}

# Its own runtime dir: verifying must not go near a live session's sockets.
mkdir -m 700 "$TMP/run"
XDG_RUNTIME_DIR="$TMP/run" timeout 60 Hyprland --verify-config \
    -c "$PWD/config/hypr/hyprland.lua" > "$TMP/out" 2>&1
rc=$?

_check "H1 Hyprland accepts config/hypr/hyprland.lua" "0" "$rc"
[ "$rc" -eq 0 ] || sed -n '/Config parsing result/,$p' "$TMP/out" \
    | grep -v "no file '/usr" | sed '/^$/d; s/^/        /' | head -n 6

[ "$FAILS" -eq 0 ] || { echo "$FAILS check(s) failed"; exit 1; }
echo "hyprland-verify: all checks passed"
