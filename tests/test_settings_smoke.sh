#!/bin/bash
# Smoke test: every dialog-driven entry point reaches its first dialog.
#
# Nothing in CI used to run these scripts, only parse them, so a script
# that cannot open its own menu read green everywhere. That is how the
# folder refactor shipped stoa-settings.sh still sourcing
#     "$(dirname …)/lib/stoa-yad.sh"
# from scripts/desktop/, where there is no lib/: the `[ -r ] && source`
# skipped it silently, _yad_select then called a stoa_yad_list that was never
# defined, and Super+S printed "command not found" to nobody and exited 0.
#
#   S1  each script asks yad for a list when started with no arguments
#   S2  …and prints no "command not found" on the way there
#   S3  the same holds when started through a symlink, which is how
#       install.sh deploys them (~/.local/bin/stoa-settings → repo file)
#
# yad, notify-send and the compositor clients are stubs: yad records how it
# was called and "cancels", so every menu returns at once. No display, no
# session bus, nothing is changed.

cd "$(dirname "$0")/.." || exit 1

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home/.local/bin" "$TMP/home/.config/stoa"
FAILS=0
_check() { # <name> <expected> <actual>
    if [ "$2" = "$3" ]; then printf '  ✓ %s\n' "$1"
    else printf '  ✗ %s: expected [%s], got [%s]\n' "$1" "$2" "$3"; FAILS=$((FAILS + 1)); fi
}

# yad "cancels" (exit 1, no selection). Everything else that could reach
# the live session is a no-op.
for c in yad notify-send hyprctl niri gsettings noctalia rclone; do
    printf '#!/bin/sh\necho "%s $*" >> "$STUB_LOG"\nexit 1\n' "$c" > "$TMP/bin/$c"
done
chmod +x "$TMP/bin/"*

# <script> → "<yad list calls> <command-not-found lines>"
_probe() {
    : > "$TMP/calls"
    env -i HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home/.config" \
        PATH="$TMP/bin:/usr/bin:/bin" TERM=dumb STUB_LOG="$TMP/calls" \
        timeout 20 bash "$1" < /dev/null > /dev/null 2> "$TMP/err"
    printf '%s %s' "$(grep -c '^yad .*--list' "$TMP/calls")" \
                   "$(grep -c 'command not found' "$TMP/err")"
}

for script in scripts/desktop/stoa-settings.sh scripts/packages/stoa-store.sh \
              scripts/health/stoa-health.sh scripts/drive/stoa-drive.sh; do
    name=$(basename "$script" .sh)
    _check "S1/S2 ${name} opens its menu" "1 0" "$(_probe "$script")"
    [ -s "$TMP/err" ] && sed 's/^/        /' "$TMP/err" | head -n 3

    ln -sf "$PWD/$script" "$TMP/home/.local/bin/$name"
    _check "S3 ${name} through the installed symlink" "1 0" \
        "$(_probe "$TMP/home/.local/bin/$name")"
done

[ "$FAILS" -eq 0 ] || { echo "$FAILS check(s) failed"; exit 1; }
echo "settings-smoke: all checks passed"
