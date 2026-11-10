#!/bin/bash
# setup/arch-install.sh must run as the single file the README hands out.
#
# The documented way in, from the Arch live ISO, is
#
#     curl -LO …/main/setup/arch-install.sh
#     chmod +x arch-install.sh && ./arch-install.sh
#
# — one file, in an otherwise empty directory. Since the AUR helpers moved
# to setup/lib/aur.sh the script opens with
#
#     source "$(dirname …)/lib/aur.sh"
#
# and next to a lone download there is no lib/. Under `set -e` that is
# fatal on line 35, before the banner: the installer has not started once
# since. Nothing caught it because every check runs inside the checkout,
# where lib/aur.sh is always there.
#
#   A1  copied alone into an empty directory, it gets as far as its own
#       "run as root" check
#   A2  …without a "No such file or directory" on the way
#
# `id` is a stub that answers 1000, so the script always stops at that check
# and can never go on to ping, download or start archinstall — which are
# stubbed out as well, in case the check ever moves.

cd "$(dirname "$0")/.." || exit 1

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/iso"
FAILS=0
_check() { # <name> <expected> <actual>
    if [ "$2" = "$3" ]; then printf '  ✓ %s\n' "$1"
    else printf '  ✗ %s: expected [%s], got [%s]\n' "$1" "$2" "$3"; FAILS=$((FAILS + 1)); fi
}

printf '#!/bin/sh\necho 1000\n' > "$TMP/bin/id"
for c in ping curl wget archinstall arch-chroot git; do
    printf '#!/bin/sh\nexit 1\n' > "$TMP/bin/$c"
done
chmod +x "$TMP/bin/"*

cp setup/arch-install.sh "$TMP/iso/arch-install.sh"
( cd "$TMP/iso" && env -i HOME="$TMP/iso" PATH="$TMP/bin:/usr/bin:/bin" TERM=dumb \
    bash ./arch-install.sh < /dev/null > "$TMP/out" 2> "$TMP/err" )

_check "A1 reaches its own root check" "yes" \
    "$(grep -q 'Run as root' "$TMP/out" && echo yes || echo no)"
_check "A2 no missing file on the way" "0" \
    "$(grep -c 'No such file or directory' "$TMP/err")"
[ -s "$TMP/err" ] && sed 's/^/        /' "$TMP/err" | head -n 3

[ "$FAILS" -eq 0 ] || { echo "$FAILS check(s) failed"; exit 1; }
echo "arch-install-standalone: all checks passed"
