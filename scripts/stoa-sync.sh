#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Sync                                          ║
# ║  Used by the `sync-stoa` shell alias.                       ║
# ║                                                              ║
# ║  Flow:                                                       ║
# ║    1. git pull --autostash                                  ║
# ║    2. Mirror live Noctalia state (curated paths).           ║
# ║    3. Mirror anything listed in ~/.config/stoa/sync.list    ║
# ║       into dotfiles/<rel-path>.                              ║
# ║    4. git add -A, commit + push if anything changed.        ║
# ║                                                              ║
# ║  Files that are already symlinked into the repo (kitty,     ║
# ║  hyprland, eww, waybar, etc.) are caught by                 ║
# ║  `git add -A` automatically — don't add them to sync.list.  ║
# ╚══════════════════════════════════════════════════════════════╝

set -e

STOA_DIR="${STOA_DIR:-$HOME/StoaLinux}"
SYNC_LIST="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/sync.list"

if [ ! -d "$STOA_DIR/.git" ]; then
    echo "stoa-sync: $STOA_DIR is not a git repo" >&2
    exit 1
fi

cd "$STOA_DIR"

# Guard: validate TOML before copying to avoid committing corrupt files.
# (Noctalia v5.) tomllib needs python 3.11+; when the
# import fails the helper exits 0 so the copy still happens, matching the
# "jq missing -> skip validation" behaviour above. A genuine parse error
# raises, so a corrupt file is skipped rather than committed.
_cp_toml() {
    local src="$1" dst="$2"
    if command -v python3 >/dev/null 2>&1; then
        if ! python3 -c '
import sys
try:
    import tomllib
except ImportError:
    sys.exit(0)
with open(sys.argv[1], "rb") as fh:
    tomllib.load(fh)
' "$src" 2>/dev/null; then
            echo "stoa-sync: SKIPPING invalid TOML: $src" >&2
            return 0
        fi
    fi
    cp "$src" "$dst"
}

git pull --autostash

# ── Noctalia v5 GUI state (snapshot only) ──
# v5 writes GUI-managed overrides to ~/.local/state/noctalia/settings.toml,
# outside the curated ~/.config/noctalia paths handled above. Mirror it so a
# bar tweak made through the Settings GUI is at least versioned.
#
# This is a SNAPSHOT, not a source. install.sh deliberately does not link it
# back, for two reasons:
#
#   * it carries machine-bound values — monitor connector names in
#     [bar.<name>.monitor.*] and per-output overrides — which are wrong on
#     any other machine;
#   * it is the layer that WINS over config/noctalia/config.toml, so
#     restoring it elsewhere would silently shadow the repo config and make
#     edits there look like they do nothing.
#
# To make a GUI tweak permanent, move it into config/noctalia/config.toml.
NOCTALIA_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/noctalia"
if [ -f "$NOCTALIA_STATE/settings.toml" ] && [ ! -L "$NOCTALIA_STATE/settings.toml" ]; then
    state_dst="$STOA_DIR/dotfiles/.local/state/noctalia/settings.toml"
    mkdir -p "$(dirname "$state_dst")"
    _cp_toml "$NOCTALIA_STATE/settings.toml" "$state_dst"
fi

# ── User-defined paths (~/.config/stoa/sync.list) ──
# Each non-comment, non-blank line is a path (~ and $VAR expanded).
# Files and directories are mirrored to dotfiles/<path-relative-to-$HOME>.
# Symlinks are skipped — they're already captured wherever they point.
if [ -f "$SYNC_LIST" ]; then
    while IFS= read -r raw || [ -n "$raw" ]; do
        # strip comments + trim
        line="${raw%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [ -z "$line" ] && continue

        # expand ~ and $VAR
        src=$(eval echo "$line")
        [ -e "$src" ] || { echo "stoa-sync: skipping missing $src" >&2; continue; }
        [ -L "$src" ] && continue   # symlinks already caught by git add

        case "$src" in
            "$HOME"/*) ;;
            *) echo "stoa-sync: skipping $src (outside \$HOME)" >&2; continue ;;
        esac

        rel="${src#"$HOME"/}"
        dst="$STOA_DIR/dotfiles/$rel"
        mkdir -p "$(dirname "$dst")"

        if [ -d "$src" ]; then
            if command -v rsync >/dev/null 2>&1; then
                rsync -a --delete --exclude='.git/' "$src/" "$dst/"
            else
                rm -rf "$dst"
                cp -a "$src" "$dst"
            fi
        else
            cp "$src" "$dst"
        fi
    done < "$SYNC_LIST"
fi

# ── Commit if anything changed ──
git add -A
if git diff --cached --quiet; then
    echo "Already up to date. Nothing to sync."
    exit 0
fi

git commit -m "$(printf 'chore: sync %s\n\nChanges:\n%s' \
    "$(date '+%Y-%m-%d %H:%M')" \
    "$(git diff --cached --name-status)")"
git push
