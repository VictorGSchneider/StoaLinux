#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Package Snapshot (pacman pre-transaction)     ║
# ║  "The wise man prepares for the worst." — Seneca             ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Called automatically by pacman before any install/upgrade/remove.
# Saves a full package list so you know exactly what changed
# if something breaks after an update.

# When run as root (pacman hook), find the real user's home
if [ "$(id -u)" -eq 0 ]; then
    _real_user=$(logname 2>/dev/null || who | awk 'NR==1{print $1}')
    _real_home=$(getent passwd "$_real_user" 2>/dev/null | cut -d: -f6)
    _real_home="${_real_home:-/root}"
else
    _real_home="$HOME"
fi
SNAPSHOT_DIR="${_real_home}/.config/stoa/pkg-snapshots"
MAX_SNAPSHOTS=20

# When invoked as the pacman hook we are root but the target dir lives in
# the user's home — create it with the user's ownership so the user can
# read/rotate their own snapshots.
if [ "$(id -u)" -eq 0 ] && [ -n "${_real_user:-}" ] && id "$_real_user" &>/dev/null; then
    install -d -m 0755 -o "$_real_user" -g "$_real_user" "$SNAPSHOT_DIR"
else
    mkdir -p "$SNAPSHOT_DIR"
fi

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

# Hand the snapshot file back to the user when invoked from the pacman
# hook, otherwise rotation by `stoa-maintain` (run as user) can't touch it.
if [ "$(id -u)" -eq 0 ] && [ -n "${_real_user:-}" ] && id "$_real_user" &>/dev/null; then
    chown "$_real_user:$_real_user" "$SNAPSHOT" 2>/dev/null
fi

# Rotate: keep only the last N snapshots
ls -1t "$SNAPSHOT_DIR"/pkg-snapshot-*.txt 2>/dev/null | tail -n +$((MAX_SNAPSHOTS + 1)) | xargs -r rm -f

echo "Stoa: snapshot saved → ${SNAPSHOT}"
