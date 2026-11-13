#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Restore                                       ║
# ║  "What you gave away, take back — carefully."                ║
# ║                                                              ║
# ║  The other half of stoa-sync: stoa-sync mirrors the files    ║
# ║  listed in ~/.config/stoa/sync.list into dotfiles/ in the    ║
# ║  repo; this puts them back under $HOME on a new machine.     ║
# ╚══════════════════════════════════════════════════════════════╝

# ── --help ──
case "${1:-}" in
    -h|--help|help)
        cat <<'STOA_HELP'
stoa-restore — copy the personal files stoa-sync mirrored in dotfiles/ back to $HOME.

USAGE
  stoa-restore [OPTION]

WHAT IT DOES
  Every file under dotfiles/<path> in the repo is restored to $HOME/<path>.
  Nothing is touched until you confirm, and a file that already exists and
  differs is first copied to <file>.bak.<timestamp>. Identical files are left
  alone, so running it twice changes nothing the second time.

  Without a terminal (a script, a pipe) and without --yes it only lists what
  it would do.

NEVER RESTORED
  .local/state/noctalia/*   machine-bound snapshot of the shell's GUI settings;
                            it would shadow config/noctalia/config.toml. Move the
                            values you want into config.toml instead.
  .ssh/* except .ssh/config, .gnupg/*   private key material
  anything whose destination is a symlink (it is managed elsewhere)

OPTIONS
  -n, --dry-run   list what would be restored, change nothing
  -y, --yes       restore without asking
  -h, --help      show this help

ENVIRONMENT
  STOA_DIR        the repo checkout (default: the one this script lives in)

RESUMO RÁPIDO
  stoa-restore
  stoa-restore -n | --dry-run
  stoa-restore -y | --yes
  stoa-restore -h | --help
STOA_HELP
        exit 0
        ;;
esac

set -u

STOA_DIR="${STOA_DIR:-$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)}"
SRC="${STOA_DIR}/dotfiles"

B='\033[38;2;196;154;92m'
S='\033[38;2;110;106;98m'
F='\033[38;2;212;207;196m'
O='\033[38;2;138;154;108m'
T='\033[38;2;179;107;90m'
R='\033[0m'

DRY_RUN=0
ASSUME_YES=0
for arg in "$@"; do
    case "$arg" in
        -n|--dry-run) DRY_RUN=1 ;;
        -y|--yes)     ASSUME_YES=1 ;;
        *) echo "stoa-restore: unknown option: $arg (try --help)" >&2; exit 2 ;;
    esac
done

if [ ! -d "$SRC" ]; then
    echo -e "  ${S}[~] No dotfiles/ in ${STOA_DIR} — nothing to restore.${R}"
    exit 0
fi

# Why a mirrored path must not be written back, or empty when it may be.
_skip_reason() {
    case "$1" in
        .local/state/noctalia/*) echo "machine-bound snapshot; promote values into config/noctalia/config.toml" ;;
        .ssh/config)             ;;
        .ssh/*)                  echo "private key material" ;;
        .gnupg/*)                echo "private key material" ;;
        .gitkeep|*/.gitkeep)     echo "placeholder" ;;
        /*|../*|*/../*|*/..|..)  echo "unsafe path" ;;
    esac
}

new_files=()
diff_files=()
skipped=()
same=0

while IFS= read -r -d '' file; do
    rel="${file#"$SRC"/}"
    reason=$(_skip_reason "$rel")
    if [ -n "$reason" ]; then
        [ "$reason" = "placeholder" ] || skipped+=("$rel  ($reason)")
        continue
    fi
    dest="${HOME}/${rel}"
    if [ -L "$dest" ]; then
        skipped+=("$rel  (destination is a symlink)")
    elif [ ! -e "$dest" ]; then
        new_files+=("$rel")
    elif cmp -s "$file" "$dest"; then
        same=$((same + 1))
    else
        diff_files+=("$rel")
    fi
done < <(find "$SRC" -type f -print0 | sort -z)

total=$(( ${#new_files[@]} + ${#diff_files[@]} ))

for rel in "${new_files[@]}";  do echo -e "  ${O}[new]    ${R}~/${rel}"; done
for rel in "${diff_files[@]}"; do echo -e "  ${B}[differs]${R} ~/${rel}  ${S}(backed up first)${R}"; done
for entry in "${skipped[@]}";  do echo -e "  ${S}[skip]    ~/${entry}${R}"; done

if [ "$total" -eq 0 ]; then
    echo -e "  ${S}[~] Nothing to restore ($same already identical, ${#skipped[@]} skipped).${R}"
    exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
    echo -e "  ${S}Dry run: $total file(s) would be restored. Nothing changed.${R}"
    exit 0
fi

if [ "$ASSUME_YES" -ne 1 ]; then
    if [ -t 0 ] && [ -t 1 ]; then
        read -r -p "  Restore $total file(s)? Existing ones are backed up first. [y/N] " answer
        case "$answer" in
            y|Y|yes|YES) ;;
            *) echo -e "  ${S}Cancelled. Nothing was changed.${R}"; exit 0 ;;
        esac
    else
        echo -e "  ${S}Not a terminal: listed only. Run ${B}stoa-restore${S} to restore, or add --yes.${R}"
        exit 0
    fi
fi

stamp=$(date +%s)
restored=0
failed=0
for rel in "${diff_files[@]}" "${new_files[@]}"; do
    src="${SRC}/${rel}"
    dest="${HOME}/${rel}"
    mkdir -p "$(dirname "$dest")" || { failed=$((failed + 1)); continue; }
    if [ -e "$dest" ]; then
        cp -p "$dest" "${dest}.bak.${stamp}" || { echo -e "  ${T}[!] backup failed, skipped: ~/${rel}${R}"; failed=$((failed + 1)); continue; }
    fi
    if cp -p "$src" "$dest"; then
        restored=$((restored + 1))
    else
        echo -e "  ${T}[!] could not restore ~/${rel}${R}"
        failed=$((failed + 1))
    fi
done

echo -e "  ${O}[✓] Restored ${restored} file(s).${R}"
[ "$failed" -gt 0 ] && { echo -e "  ${T}[!] ${failed} failed.${R}"; exit 1; }
exit 0
