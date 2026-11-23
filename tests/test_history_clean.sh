#!/bin/bash
# Behavioural test for scripts/tools/stoa-history.py.
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
#   P5  a zsh entry whose text ends in a backslash does not swallow the
#       entry after it. The backslash is zsh's line continuation, but the
#       next line opening `: <epoch>:<n>;` is a new entry, not a
#       continuation of this one. Getting that wrong is silent: the
#       swallowed entry rides along inside a blob, is never classified by
#       any pass, and the prune quietly stops finding anything
#   P6  a pasted command (`cmd\` + blank line, which is what a paste with
#       a trailing newline leaves behind) is trimmed back to one line with
#       its text and timestamp intact — and left alone under
#       --no-trim-pastes
#   P7  --drop-multiline removes a genuine multi-line entry and keeps the
#       pasted one, which is a one-line command wearing two lines
#   P8  --similar prunes one-shot actions (pacman -S/-Rns, git branch -d)
#       and keeps only the latest of a family of near-identical lines, and
#       does neither without the flag. Short distinct commands, the keep
#       list and a bare `pacman -Syu` must survive. Typos (`git brach`,
#       `store refresh7` beside `store refresh`) go; the corrected line stays
#
# Everything runs under HOME=$TMP: the test must never read, and can never
# write, the history of whoever is running it.

cd "$(dirname "$0")/.." || exit 1

SCRIPT="scripts/tools/stoa-history.py"
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

# ── P5: a trailing backslash must not eat the next entry ─────────────
# Pasting a command with a newline at the end is how a real history fills
# up with backslash-terminated entries: zsh stores "cmd\" plus an empty
# line. That one is a genuine continuation and must still join; an entry
# header on the next line must not.
cat > "$TMP/.zsh_history" <<ZSH
: ${NOW}:0;grep -rn foo . \\
: ${NOW}:0;clear
: ${NOW}:0;sudo pacman -S qt6-wayland\\

: ${NOW}:0;ls
ZSH
rm -f "$TMP/.bash_history" "$TMP/.python_history"
out=$(_stoa clean --aggressive --days 0)
case "$out" in
    *"noise"*) ;;
    *) _fail "the entry after a backslash-terminated one was swallowed:" \
             "neither 'clear' nor 'ls' was classified as noise" ;;
esac
# Both noise entries have to be found — one after the backslash line, one
# after the paste artifact.
if ! printf '%s' "$out" | grep -qE 'noise +2'; then
    _fail "expected 2 noise entries past the backslash lines, got: $(
        printf '%s' "$out" | grep -E 'noise' || echo none)"
fi
# ... and the paste artifact itself still joins with its blank line, so the
# file holds 4 entries, not 5.
if ! printf '%s' "$out" | grep -q '4 entries'; then
    _fail "the paste artifact (cmd\\ + blank line) was not read as one entry: $(
        printf '%s' "$out" | grep -E 'entries' | head -1)"
fi

# ── P6 / P7: paste artefacts vs. genuine multi-line entries ──────────
_multiline_fixture() {
    rm -f "$TMP/.bash_history" "$TMP/.python_history"
    cat > "$TMP/.zsh_history" <<ZSH
: ${NOW}:0;sudo pacman -S qt6-wayland\\

: ${NOW}:0;for i in 1 2; do\\
echo \$i\\
done
: ${NOW}:0;git status
ZSH
}

_multiline_fixture
_stoa clean --apply --yes --days 0 --drop-multiline > /dev/null
_kept "$TMP/.zsh_history" "sudo pacman -S qt6-wayland" "a pasted command"
_gone "$TMP/.zsh_history" "for i in 1 2"  "a multi-line entry under --drop-multiline"
if ! grep -qx ": ${NOW}:0;sudo pacman -S qt6-wayland" "$TMP/.zsh_history"; then
    _fail "the trimmed paste lost its timestamp header or its text:" \
          "$(grep -m1 pacman "$TMP/.zsh_history")"
fi
if grep -q '\\$' "$TMP/.zsh_history"; then
    _fail "a trimmed paste still carries its continuation backslash"
fi
if [ "$(wc -l < "$TMP/.zsh_history")" != "2" ]; then
    _fail "expected 2 lines after trimming one paste and dropping the loop," \
          "got $(wc -l < "$TMP/.zsh_history")"
fi

# --no-trim-pastes leaves the artefact exactly as the shell wrote it.
_multiline_fixture
before_paste=$(md5sum < "$TMP/.zsh_history")
_stoa clean --apply --yes --days 0 --no-trim-pastes > /dev/null
if ! grep -q 'qt6-wayland\\$' "$TMP/.zsh_history"; then
    _fail "--no-trim-pastes rewrote the paste artefact anyway"
fi
[ "$(md5sum < "$TMP/.zsh_history")" = "$before_paste" ] || \
    _fail "--no-trim-pastes changed a file it had nothing to remove from"

# ── P4: restore puts the file back ───────────────────────────────────
_fixture
before_bash=$(md5sum < "$TMP/.bash_history")
before_zsh=$(md5sum < "$TMP/.zsh_history")
_stoa clean --apply --yes > /dev/null
_stoa restore --yes > /dev/null
[ "$(md5sum < "$TMP/.bash_history")" = "$before_bash" ] || \
    _fail "restore did not reproduce the pre-clean ~/.bash_history"
[ "$(md5sum < "$TMP/.zsh_history")" = "$before_zsh" ] || \
    _fail "restore did not reproduce the pre-clean ~/.zsh_history"

# ── P8: --similar ────────────────────────────────────────────────────
rm -f "$TMP/.bash_history" "$TMP/.python_history"
cat > "$TMP/.zsh_history" <<ZSH
: ${NOW}:0;sudo pacman -S gparted
: ${NOW}:0;sudo pacman -Rns ufw vlc
: ${NOW}:0;yay -S jan-bin
: ${NOW}:0;git branch -d helper-design
: ${NOW}:0;sudo pacman -Syu
: ${NOW}:0;sudo smartctl -a /dev/nvme1n1
: ${NOW}:0;sudo smartctl -a /dev/nvme1n2
: ${NOW}:0;sudo smartctl -a /dev/nvme1n3
: ${NOW}:0;stoa-drive sync-all
: ${NOW}:0;stoa-drive sync-status
: ${NOW}:0;docker compose up -d --build api
: ${NOW}:0;docker compose up -d --build apj
: ${NOW}:0;git brach
: ${NOW}:0;git status
: ${NOW}:0;git branc main
: ${NOW}:0;git branch main
: ${NOW}:0;./store refresh7
: ${NOW}:0;./store refresh
ZSH
plain=$(_stoa clean --days 0)
case "$plain" in
    *disposable*|*similar*) _fail "disposable/similar ran without --similar" ;;
esac
out=$(_stoa clean --similar --days 0)
printf '%s' "$out" | grep -qE 'disposable +4' || \
    _fail "expected 4 disposable entries (2 pacman, yay, git branch -d), got: $(
        printf '%s' "$out" | grep disposable || echo none)"
printf '%s' "$out" | grep -qE 'similar +2' || \
    _fail "expected the 2 older smartctl lines as similar, got: $(
        printf '%s' "$out" | grep -E 'similar' || echo none)"
printf '%s' "$out" | grep -q 'keeping    9 of 18' || \
    _fail "expected to keep 9 of 18 (Syu, last smartctl, 2 stoa-drive, 2 docker, git status, git branch main, store refresh), got: $(
        printf '%s' "$out" | grep keeping || echo none)"
printf '%s' "$out" | grep -qE 'typo +3' || \
    _fail "expected 3 typos (git brach, git branc main, store refresh7), got: $(
        printf '%s' "$out" | grep -E 'typo' || echo none)"
_stoa clean --similar --days 0 --apply --yes > /dev/null
grep -q 'smartctl -a /dev/nvme1n3' "$TMP/.zsh_history" || \
    _fail "--similar did not keep the most recent smartctl line"
grep -q 'pacman -Syu' "$TMP/.zsh_history" || \
    _fail "--similar removed a bare pacman -Syu"
grep -q 'stoa-drive sync-status' "$TMP/.zsh_history" || \
    _fail "--similar merged two short, distinct commands"

if [ "$status" -eq 0 ]; then
    echo "history-clean: ok"
else
    echo "" >&2
    echo "A history rewrite may only remove the entries it reported." >&2
fi
exit "$status"
