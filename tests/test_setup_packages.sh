#!/bin/bash
# Every package the setup scripts install by name must exist in Arch's own
# repositories (core, extra, multilib).
#
# post-install.sh hands its whole list to one `sudo pacman -S --needed`, and
# archinstall does the same with setup/archinstall/user_configuration.json.
# pacman refuses the entire transaction over a single unknown name
# ("error: target not found"), and under `set -e` that is where the install
# ends. The README's first line promises Arch Linux *and* CachyOS, but the
# lists were only ever run on CachyOS, whose extra repositories supply names
# plain Arch does not have: pwvucontrol is in `cachyos` and nowhere in
# core/extra/multilib, so on Arch neither path gets past its package step.
#
#   A1  every name in post-install.sh's ALL_PKGS resolves in core, extra or
#       multilib — as a package, a group, or something one of them provides
#   A2  the same for the archinstall package list
#
# Needs pacman with synced databases, so it only runs on an Arch-based
# machine and skips elsewhere (CI included). It reads the databases and
# installs nothing.

cd "$(dirname "$0")/.." || exit 1
command -v pacman >/dev/null || { echo "pacman missing — skipped (Arch-only check)"; exit 0; }
command -v python3 >/dev/null || { echo "python3 missing — skipped"; exit 0; }

ARCH_NAMES=$(pacman -Sl core extra multilib 2>/dev/null | awk '{print $2}' | sort -u)
[ -n "$ARCH_NAMES" ] || { echo "no synced core/extra/multilib databases — skipped"; exit 0; }

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
FAILS=0
_check() { # <name> <expected> <actual>
    if [ "$2" = "$3" ]; then printf '  ✓ %s\n' "$1"
    else printf '  ✗ %s: expected [%s], got [%s]\n' "$1" "$2" "$3"; FAILS=$((FAILS + 1)); fi
}

# True when Arch itself can install $1: a package or group in its repos, or
# a name one of their packages provides (ttf-font-awesome → woff2-font-awesome).
_in_arch() {
    printf '%s\n' "$ARCH_NAMES" | grep -qxF -- "$1" && return 0
    pacman -Sg "$1" >/dev/null 2>&1 && return 0
    case "$(pacman -Sp --print-format '%r' "$1" 2>/dev/null | head -n1)" in
        core|extra|multilib) return 0 ;;
    esac
    return 1
}
_missing() { # <names…> → the ones Arch cannot install, space-separated
    local p out=""
    for p in $(printf '%s\n' "$@" | sort -u); do
        _in_arch "$p" || out+="${out:+ }$p"
    done
    printf '%s' "$out"
}

# post-install.sh builds ALL_PKGS from plain assignments and two `case`
# blocks on the compositor choice; "both" is the superset. Evaluating that
# stretch runs no command with an effect.
POST_PKGS=$(
    HOME="$TMP" WM_CHOICE=both
    eval "$(awk '/^HYPR_PKGS=/{on=1} on{print} /^ALL_PKGS=/{exit}' setup/post-install.sh)"
    printf '%s' "$ALL_PKGS"
)
JSON_PKGS=$(python3 -I -c '
import json, sys
print(" ".join(json.load(open(sys.argv[1]))["packages"]))' setup/archinstall/user_configuration.json)

_check "A0 the lists were read" "yes" \
    "$([ "$(echo $POST_PKGS | wc -w)" -gt 50 ] && [ "$(echo $JSON_PKGS | wc -w)" -gt 30 ] && echo yes || echo no)"
# shellcheck disable=SC2086
_check "A1 post-install.sh: all names exist in Arch's repositories" "" "$(_missing $POST_PKGS)"
# shellcheck disable=SC2086
_check "A2 archinstall list: all names exist in Arch's repositories" "" "$(_missing $JSON_PKGS)"

[ "$FAILS" -eq 0 ] || { echo "$FAILS check(s) failed"; exit 1; }
echo "setup-packages: all checks passed"
