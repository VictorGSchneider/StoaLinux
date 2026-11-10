#!/bin/bash
# install.sh must finish on a home directory that has never seen Stoa.
#
# README offers it on its own ("Dotfiles only: ./install.sh") and
# arch-install.sh runs it in the freshly installed system. Both are a $HOME
# with no ~/.config/stoa — and there install.sh stopped half-way:
#
#     ln: failed to create symbolic link '~/.config/stoa/wallpapers':
#         No such file or directory
#
# The wallpaper migration links ~/.config/stoa/wallpapers before anything
# has created ~/.config/stoa, and under `set -e` that is the end of the run:
# no stoa-* command in ~/.local/bin, no pacman hooks, no polkit rule, no
# stoa.conf. post-install.sh hid it by creating the directory first, and
# arch-install.sh hid it behind `2>/dev/null || true` and a success message.
#
#   I1  exits 0 on an empty $HOME
#   I2  the stoa-* commands are linked (the Scripts section was reached)
#   I3  stoa.conf is seeded
#   I4  the pacman hook step was reached
#   I5  a second run changes nothing: exits 0 and leaves no *.bak.* backups
#
# sudo is a stub that records what it was asked and runs nothing (only the
# read-only test/readlink/cmp are passed through); systemctl, noctalia,
# crontab, pipx and the network clients are stubs too. Everything install.sh
# writes lands in a temporary $HOME.

cd "$(dirname "$0")/.." || exit 1

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home"
FAILS=0
_check() { # <name> <expected> <actual>
    if [ "$2" = "$3" ]; then printf '  ✓ %s\n' "$1"
    else printf '  ✗ %s: expected [%s], got [%s]\n' "$1" "$2" "$3"; FAILS=$((FAILS + 1)); fi
}

cat > "$TMP/bin/sudo" <<'STUB'
#!/bin/bash
echo "sudo $*" >> "$STUB_LOG"
case "$1" in
    test|readlink|cmp) exec "$@" ;;
esac
exit 0
STUB
for c in systemctl noctalia crontab curl wget; do
    printf '#!/bin/sh\nexit 1\n' > "$TMP/bin/$c"
done
for c in pipx faillock; do
    printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/$c"
done
chmod +x "$TMP/bin/"*

_install() { # → exit status; output in $TMP/out
    env -i HOME="$TMP/home" PATH="$TMP/bin:/usr/bin:/bin" TERM=dumb \
        STUB_LOG="$TMP/sudo.log" bash install.sh > "$TMP/out" 2>&1
    echo $?
}

rc=$(_install)
_check "I1 exits 0 on an empty home" "0" "$rc"
[ "$rc" = 0 ] || { echo "      last lines of its output:"; tail -n 3 "$TMP/out" | sed 's/^/        /'; }

_check "I2 stoa-settings is linked" "$PWD/scripts/desktop/stoa-settings.sh" \
    "$(readlink "$TMP/home/.local/bin/stoa-settings" 2>/dev/null)"
_check "I3 stoa.conf is seeded" "yes" \
    "$([ -f "$TMP/home/.config/stoa/stoa.conf" ] && echo yes || echo no)"
_check "I4 the pacman hook step was reached" "yes" \
    "$(grep -q '/etc/pacman.d/hooks/stoa-pkg-snapshot.hook' "$TMP/sudo.log" 2>/dev/null && echo yes || echo no)"

rc=$(_install)
_check "I5 a second run exits 0" "0" "$rc"
_check "I5 …and backs nothing up" "0" \
    "$(find "$TMP/home" -name '*.bak.*' 2>/dev/null | wc -l)"

[ "$FAILS" -eq 0 ] || { echo "$FAILS check(s) failed"; exit 1; }
echo "install-fresh-home: all checks passed"
