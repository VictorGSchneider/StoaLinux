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
# ║  Files that are already symlinked into the repo (rofi,      ║
# ║  kitty, hyprland, eww, waybar, etc.) are caught by          ║
# ║  `git add -A` automatically — don't add them to sync.list.  ║
# ╚══════════════════════════════════════════════════════════════╝

set -e

STOA_DIR="${STOA_DIR:-$HOME/StoaLinux}"
NOCTALIA="${XDG_CONFIG_HOME:-$HOME/.config}/noctalia"
SYNC_LIST="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/sync.list"

if [ ! -d "$STOA_DIR/.git" ]; then
    echo "stoa-sync: $STOA_DIR is not a git repo" >&2
    exit 1
fi

cd "$STOA_DIR"

git pull --autostash

# ── Noctalia (curated) ──
if [ -d "$NOCTALIA" ]; then
    for f in settings.json colors.json; do
        if [ -f "$NOCTALIA/$f" ]; then
            cp "$NOCTALIA/$f" "$STOA_DIR/config/noctalia/$f"
        fi
    done

    if [ -d "$NOCTALIA/plugins" ]; then
        for pd in "$NOCTALIA/plugins"/*/; do
            [ -d "$pd" ] || continue
            name=$(basename "$pd")
            src="$pd/settings.json"
            [ -f "$src" ] || continue
            dst="$STOA_DIR/config/noctalia/plugins/$name/settings.json"
            mkdir -p "$(dirname "$dst")"
            cp "$src" "$dst"
        done
    fi

    if [ -d "$NOCTALIA/colorschemes" ]; then
        for cs in "$NOCTALIA/colorschemes"/*/; do
            target="${cs%/}"
            [ -d "$target" ] || continue
            [ -L "$target" ] && continue
            name=$(basename "$target")
            src="$target/$name.json"
            [ -f "$src" ] || continue
            dst="$STOA_DIR/config/noctalia/colorschemes/$name/$name.json"
            mkdir -p "$(dirname "$dst")"
            cp "$src" "$dst"
        done
    fi
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
