#!/usr/bin/env bash
# Re-apply the screen-toolkit screenshot-delay patch after Noctalia's
# plugin autoUpdate overwrites the installed copy. Idempotent: running
# it twice in a row is safe.
#
# Usage:
#   theme/noctalia-plugin-patches/screen-toolkit/apply.sh
#
# After it returns success, restart noctalia so the QML reloads:
#   killall quickshell && ~/.local/bin/stoa-bar &

set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
PATCH="${HERE}/0001-screenshot-delay.patch"

# Try the two install locations Noctalia uses depending on version.
PLUGIN_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/noctalia/plugins/screen-toolkit"
[ -d "$PLUGIN_DIR" ] || \
    PLUGIN_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/noctalia/plugins/screen-toolkit"

[ -d "$PLUGIN_DIR" ] || {
    echo "ERROR: screen-toolkit plugin directory not found." >&2
    echo "       Looked in:" >&2
    echo "         ${XDG_CONFIG_HOME:-$HOME/.config}/noctalia/plugins/screen-toolkit" >&2
    echo "         ${XDG_DATA_HOME:-$HOME/.local/share}/noctalia/plugins/screen-toolkit" >&2
    exit 1
}
[ -f "$PATCH" ] || { echo "ERROR: patch file missing: $PATCH" >&2; exit 1; }

echo "Plugin dir: $PLUGIN_DIR"
echo "Patch     : $PATCH"

cd "$PLUGIN_DIR"

# Idempotency: --reverse --dry-run succeeds when the patch is already applied.
if patch -p1 --reverse --dry-run --silent < "$PATCH" >/dev/null 2>&1; then
    echo "Already applied — nothing to do."
    exit 0
fi

# Fail before touching anything if the diff wouldn't apply cleanly.
if ! patch -p1 --dry-run --silent < "$PATCH" >/dev/null 2>&1; then
    echo "ERROR: patch does not apply cleanly to the current plugin sources." >&2
    echo "       Upstream may have moved — open the .patch file and re-create" >&2
    echo "       the diff against the new screen-toolkit/{Main,Settings}.qml." >&2
    exit 2
fi

patch -p1 < "$PATCH"
echo
echo "Patch applied. Restart noctalia to load the change:"
echo "  killall quickshell && ~/.local/bin/stoa-bar &"
