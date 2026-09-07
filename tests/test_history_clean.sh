#!/bin/bash
# Behavioural test for scripts/stoa-history.py.
#
# The script rewrites the files that hold every command you have ever run,
# so the failure mode is not a crash — it is a history file that came back
# subtly wrong, and no way to notice until you reach for a command that is
# no longer there. Four properties are checked against a sandbox $HOME:
#
#   P1  a dry run writes nothing at all
#   P2  --apply removes exactly the classes it reported, and nothing else:
#       the multi-line bash entry, the zsh continuation line and the
#       keep-list regex all survive byte-for-byte
#   P3  bytes that are not UTF-8 round-trip unchanged. zsh metafies every
#       byte >= 0x80, so a history with an accented character decodes to
#       surrogates — encoding those back naively raises, and re-encoding
#       them "helpfully" corrupts the line
#   P4  restore puts the pre-clean file back
#
# Everything runs under HOME=$TMP: the test must never read, and can never
# write, the history of whoever is running it.

cd "$(dirname "$0")/.." || exit 1

SCRIPT="scripts/stoa-history.py"
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

NOW=$(date +%s)
OLD=$((NOW - 500 * 86400))
status=0

_fail() {
    echo "history-clean: $*"
    status=1
}

# stoa-history with the sandbox as $HOME, never the real one.
_stoa() {
    HOME="$TMP" XDG_STATE_HOME="$TMP/.local/state" XDG_CONFIG_HOME="$TMP/.config" \
        python3 "$SCRIPT" "$@" 2>&1
}

_fixture() {
    mkdir -p "$TMP/.config/stoa"
    printf '^docker compose\n' > "$TMP/.config/stoa/history-keep"

    {
        printf '#%s\nls -la\n' "$OLD"                 # noise
        printf '#%s\ncd /tmp/scratch\n' "$OLD"        # junk
        printf '#%s\ngit status\n' "$NOW"             # duplicate (older copy)
        printf '#%s\ngit status\n' "$NOW"             # survivor
        printf '#%s\nexport TOKEN=ghp_abcdefghijklmnopqrstuvwxyz012345\n' "$NOW"
        printf '#%s\nfor i in 1 2 3; do\n  echo $i\ndone\n' "$NOW"   # multi-line
        printf '#%s\ndocker compose up -d\n' "$NOW"   # kept by the keep list
        printf '#%s\ndocker compose up -d\n' "$NOW"   # ... both copies of it
    } > "$TMP/.bash_history"

    # \203\251 is a metafied é as zsh writes it: not valid UTF-8.
    {
        printf ': %s:0;ls\n' "$OLD"
        printf ': %s:0;vim ~/notes.md\n' "$NOW"
        printf ': %s:0;vim ~/notes.md\n' "$NOW"
        printf ': %s:0;echo "line 1" \\\n"line 2"\n' "$NOW"
        printf ': %s:0;echo caf\203\251\n' "$NOW"
    } > "$TMP/.zsh_history"
}

# ── P1: a dry run is read-only ───────────────────────────────────────
_fixture
before_bash=$(md5sum < "$TMP/.bash_history")
before_zsh=$(md5sum < "$TMP/.zsh_history")
out=$(_stoa clean)
case "$out" in
    *"Dry run"*) ;;
    *) _fail "clean without --apply did not announce a dry run" ;;
esac
[ "$(md5sum < "$TMP/.bash_history")" = "$before_bash" ] || \
    _fail "clean without --apply rewrote ~/.bash_history"
[ "$(md5sum < "$TMP/.zsh_history")" = "$before_zsh" ] || \
    _fail "clean without --apply rewrote ~/.zsh_history"

# ── P2 / P3: --apply removes the reported classes and nothing else ───
_stoa clean --apply --yes > /dev/null

_gone() {
    if grep -qF -- "$2" "$1"; then
        _fail "$3 survived the prune: $2"
    fi
}
_kept() {
    if ! grep -qF -- "$2" "$1"; then
        _fail "$3 was removed, and should not have been: $2"
    fi
}

_gone "$TMP/.bash_history" "ls -la"          "a noise entry"
_gone "$TMP/.bash_history" "cd /tmp/scratch" "a /tmp junk entry"
_gone "$TMP/.bash_history" "ghp_"            "a line carrying a token"
_kept "$TMP/.bash_history" "git status"      "the most recent copy of a duplicate"
_kept "$TMP/.bash_history" "for i in 1 2 3; do" "a multi-line entry"
_kept "$TMP/.bash_history" "  echo \$i"      "the body of a multi-line entry"
_kept "$TMP/.bash_history" "done"            "the tail of a multi-line entry"

[ "$(grep -c '^git status$' "$TMP/.bash_history")" = "1" ] || \
    _fail "the duplicate pass kept the wrong number of copies of 'git status'"
[ "$(grep -c 'docker compose up -d' "$TMP/.bash_history")" = "2" ] || \
    _fail "an entry matching the keep list was deduplicated anyway"

_gone "$TMP/.zsh_history" ";ls"              "a noise entry in zsh"
_kept "$TMP/.zsh_history" 'echo "line 1" \'  "a zsh multi-line entry"
_kept "$TMP/.zsh_history" '"line 2"'         "the continuation of a zsh entry"
[ "$(grep -c 'vim ~/notes.md' "$TMP/.zsh_history")" = "1" ] || \
    _fail "the duplicate pass kept the wrong number of copies of 'vim ~/notes.md'"

# The metafied byte pair has to come out of the rewrite exactly as it went in.
if ! od -An -c "$TMP/.zsh_history" | tr -d ' \n' | grep -q '203251'; then
    _fail "a non-UTF-8 (zsh-metafied) byte sequence did not survive the rewrite"
fi

# ── P4: restore puts the file back ───────────────────────────────────
_stoa restore --yes > /dev/null
[ "$(md5sum < "$TMP/.bash_history")" = "$before_bash" ] || \
    _fail "restore did not reproduce the pre-clean ~/.bash_history"
[ "$(md5sum < "$TMP/.zsh_history")" = "$before_zsh" ] || \
    _fail "restore did not reproduce the pre-clean ~/.zsh_history"

if [ "$status" -eq 0 ]; then
    echo "history-clean: ok"
else
    echo "" >&2
    echo "A history rewrite may only remove the entries it reported." >&2
fi
exit "$status"
