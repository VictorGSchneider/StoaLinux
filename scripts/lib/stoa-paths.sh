# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Where Stoa's own files live                   ║
# ║  "A place for each thing, and each thing in its place."      ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Sourced by stoa-maintain, stoa-settings and stoa-vitals-status. They
# each used to spell "$HOME/..." out for themselves, which is how one of
# them ended up writing backups to the working directory while the other
# two looked for them in $HOME. One definition, no drift.
#
# Everything generated goes under $XDG_STATE_HOME/stoa instead of the top
# of $HOME: these are neither config nor cache, and a home directory is
# not a spool. The restore browser reads the same variables, so nothing
# became harder to find by moving.

STOA_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/stoa"
STOA_BACKUP_DIR="${STOA_STATE_DIR}/backups"
STOA_LOG_DIR="${STOA_STATE_DIR}/logs"

# Create the tree. Safe to call repeatedly.
stoa_paths_init() {
    mkdir -p "$STOA_BACKUP_DIR" "$STOA_LOG_DIR" 2>/dev/null
}

# Older releases dropped these at the top of $HOME. Move what is there so
# the restore browser keeps seeing it and $HOME stops collecting them.
# Only the three names Stoa itself produces are touched — a .zip or .log
# you made is not one of them. `mv -n` never overwrites, so a name that
# already exists in the destination is left where it is rather than
# clobbering the newer copy.
#
# Callers that only read (a status poller, say) should not call this.
stoa_paths_migrate() {
    stoa_paths_init || return 0
    local moved=0 f
    for f in "$HOME"/*.confs.*.zip "$HOME"/pre_restore_*.zip; do
        [ -f "$f" ] || continue
        mv -n "$f" "$STOA_BACKUP_DIR/" 2>/dev/null && moved=$((moved + 1))
    done
    for f in "$HOME"/backup_*.log; do
        [ -f "$f" ] || continue
        mv -n "$f" "$STOA_LOG_DIR/" 2>/dev/null && moved=$((moved + 1))
    done
    [ "$moved" -gt 0 ] && \
        echo "stoa: moved ${moved} file(s) from $HOME into $STOA_STATE_DIR" >&2
    return 0
}
