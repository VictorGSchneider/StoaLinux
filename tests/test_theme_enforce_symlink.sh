#!/bin/bash
# The pacman theme hook must leave ~/.config/gtk-4.0/settings.ini alone when
# there is nothing to change.
#
# install.sh deploys that file as a symlink into the checkout. The hook
# (theme/pacman-hooks/stoa-theme-enforce, run as root after every install or
# upgrade) then "syncs" it with four `sed -i` calls, and sed -i replaces the
# path with a new regular file — so the first pacman transaction after every
# install.sh turns the link into a stale copy, and the next install.sh finds
# a regular file where its link should be, backs it up and links again. On
# the machine this was found on: a regular file stamped with the time of the
# last `pacman -Syu`, and twelve settings.ini.bak.<epoch> beside it.
#
#   E1  with GTK 4 already carrying GTK 3's values, the file is still a
#       symlink after the hook ran
#   E2  …and what it points at is byte-for-byte unchanged
#   E3  the hook still did its real job (applied the theme through gsettings)
#
# getent, su, gsettings and dconf are stubs: getent answers with a temporary
# home, su records the command it was handed instead of running it.

cd "$(dirname "$0")/.." || exit 1

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
H="$TMP/home"
mkdir -p "$TMP/bin" "$TMP/src/gtk-3.0" "$TMP/src/gtk-4.0" \
         "$H/.config/gtk-3.0" "$H/.config/gtk-4.0"
FAILS=0
_check() { # <name> <expected> <actual>
    if [ "$2" = "$3" ]; then printf '  ✓ %s\n' "$1"
    else printf '  ✗ %s: expected [%s], got [%s]\n' "$1" "$2" "$3"; FAILS=$((FAILS + 1)); fi
}

# The shipped pair, linked the way install.sh links it.
cp theme/gtk-3.0/settings.ini "$TMP/src/gtk-3.0/settings.ini"
cp theme/gtk-4.0/settings.ini "$TMP/src/gtk-4.0/settings.ini"
cp "$TMP/src/gtk-4.0/settings.ini" "$TMP/gtk4.before"
ln -s "$TMP/src/gtk-3.0/settings.ini" "$H/.config/gtk-3.0/settings.ini"
ln -s "$TMP/src/gtk-4.0/settings.ini" "$H/.config/gtk-4.0/settings.ini"

cat > "$TMP/bin/getent" <<STUB
#!/bin/sh
[ "\$1" = passwd ] && echo "tester:x:1000:1000::$H:/bin/sh"
STUB
printf '#!/bin/sh\necho "$*" >> "$STUB_LOG"\nexit 0\n' > "$TMP/bin/su"
for c in gsettings dconf; do printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/$c"; done
chmod +x "$TMP/bin/"*

env -i HOME=/nonexistent USER=root SUDO_USER=tester PATH="$TMP/bin:/usr/bin:/bin" \
    STUB_LOG="$TMP/su.log" bash theme/pacman-hooks/stoa-theme-enforce > /dev/null 2>&1

_check "E1 gtk-4.0/settings.ini is still a symlink" "symlink" \
    "$([ -L "$H/.config/gtk-4.0/settings.ini" ] && echo symlink || echo 'regular file')"
_check "E2 its target is unchanged" "same" \
    "$(cmp -s "$TMP/gtk4.before" "$TMP/src/gtk-4.0/settings.ini" && echo same || echo changed)"
_check "E3 the theme was still applied" "yes" \
    "$(grep -q "gtk-theme 'Adwaita-dark'" "$TMP/su.log" 2>/dev/null && echo yes || echo no)"

[ "$FAILS" -eq 0 ] || { echo "$FAILS check(s) failed"; exit 1; }
echo "theme-enforce-symlink: all checks passed"
