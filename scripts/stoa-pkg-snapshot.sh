#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Package Snapshot (pacman pre-transaction)     ║
# ║  "The wise man prepares for the worst." — Seneca             ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Called automatically by pacman before any install/upgrade/remove.
# Saves a full package list so you know exactly what changed
# if something breaks after an update.

SNAPSHOT_DIR="${HOME:-/root}/.config/stoa/pkg-snapshots"
MAX_SNAPSHOTS=20

mkdir -p "$SNAPSHOT_DIR"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SNAPSHOT="${SNAPSHOT_DIR}/pkg-snapshot-${TIMESTAMP}.txt"

# Save full package list with versions
pacman -Q > "$SNAPSHOT" 2>/dev/null

# Also record which packages are explicitly installed vs dependencies
{
    echo "# Stoa Package Snapshot — ${TIMESTAMP}"
    echo "# Total packages: $(wc -l < "$SNAPSHOT")"
    echo "# Explicit: $(pacman -Qe 2>/dev/null | wc -l)"
    echo "# AUR/foreign: $(pacman -Qm 2>/dev/null | wc -l)"
    echo "#"
    cat "$SNAPSHOT"
} > "${SNAPSHOT}.tmp" && mv "${SNAPSHOT}.tmp" "$SNAPSHOT"

# Rotate: keep only the last N snapshots
ls -1t "$SNAPSHOT_DIR"/pkg-snapshot-*.txt 2>/dev/null | tail -n +$((MAX_SNAPSHOTS + 1)) | xargs -r rm -f

echo "Stoa: snapshot saved → ${SNAPSHOT}"
