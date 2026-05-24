#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Sync                                          ║
# ║  Used by the `sync-stoa` shell alias.                       ║
# ║                                                              ║
# ║  Flow:                                                       ║
# ║    1. git pull --autostash                                  ║
# ║    2. Mirror live Noctalia state into the repo:             ║
# ║         settings.json, colors.json,                          ║
# ║         plugins/<id>/settings.json (each plugin),           ║
# ║         colorschemes/<name>/<name>.json (custom only —      ║
# ║         the Stoa scheme is already a symlink).               ║
# ║       Plugin source code (QML/manifest) stays owned by      ║
# ║       Noctalia's plugin-manager.                             ║
# ║    3. git add -A, commit + push if anything changed.        ║
# ║                                                              ║
# ║  NOTE: settings.json may include host-specific paths (e.g.  ║
# ║  ~/.face for avatar, your Pictures dir). Once you sync this ║
# ║  becomes the snapshot the repo holds — sanitize manually if  ║
# ║  you'd rather not publish those.                             ║
# ╚══════════════════════════════════════════════════════════════╝

set -e

STOA_DIR="${STOA_DIR:-$HOME/StoaLinux}"
NOCTALIA="${XDG_CONFIG_HOME:-$HOME/.config}/noctalia"

if [ ! -d "$STOA_DIR/.git" ]; then
    echo "stoa-sync: $STOA_DIR is not a git repo" >&2
    exit 1
fi

cd "$STOA_DIR"

git pull --autostash

# ── Mirror Noctalia state ──
if [ -d "$NOCTALIA" ]; then
    # Top-level: main settings + selected-scheme cache.
    for f in settings.json colors.json; do
        if [ -f "$NOCTALIA/$f" ]; then
            cp "$NOCTALIA/$f" "$STOA_DIR/config/noctalia/$f"
        fi
    done

    # Per-plugin settings (skip QML/manifest/etc.).
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

    # Custom color schemes (Stoa is a symlink — skip to avoid copying
    # the repo into itself).
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
