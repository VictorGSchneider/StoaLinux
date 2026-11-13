#!/bin/bash
# Behavioural test for scripts/tools/stoa-restore.sh.
#
# It writes into $HOME, so the failure mode that matters is not a crash but a
# file you cared about quietly replaced. Properties checked against a sandbox
# $HOME and a fixture repo:
#
#   R1  a dry run writes nothing
#   R2  without a terminal and without --yes it only lists: nothing is written
#   R3  --yes restores new files, creating missing directories, and keeps the
#       file mode (a 0600 ssh config must not turn world-readable)
#   R4  a file that exists and differs is backed up to <file>.bak.<stamp> with
#       its old content, then replaced
#   R5  an identical file is left alone: no backup, no rewrite
#   R6  the Noctalia GUI snapshot, private keys under .ssh/ (but not
#       .ssh/config), .gnupg/ and anything whose destination is a symlink are
#       never written
#   R7  running it again changes nothing and makes no new backups
#   R8  a repo without dotfiles/ is not an error
#   R9  paths with spaces survive
#
# Everything runs under HOME=$TMP/home and STOA_DIR=$TMP/repo: the test can
# neither read nor write the real home of whoever runs it.

cd "$(dirname "$0")/.." || exit 1

SCRIPT="$PWD/scripts/tools/stoa-restore.sh"
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

fails=0
fail() { echo "FAIL $1"; shift; [ $# -gt 0 ] && printf '     %s\n' "$@"; fails=$((fails + 1)); }

REPO="$TMP/repo"
H="$TMP/home"
mkdir -p "$REPO/dotfiles" "$H"

mk() { mkdir -p "$(dirname "$1")"; printf '%s' "$2" > "$1"; }

# Fixture: what stoa-sync would have mirrored.
mk "$REPO/dotfiles/.zshrc"                                   "export FROM=repo"
mk "$REPO/dotfiles/.gitconfig"                               "[user] name = repo"
mk "$REPO/dotfiles/.config/app/same.conf"                    "identical"
mk "$REPO/dotfiles/.config/my app/with space.conf"           "spaces ok"
mk "$REPO/dotfiles/.ssh/config"                              "Host *"
chmod 600 "$REPO/dotfiles/.ssh/config"
mk "$REPO/dotfiles/.ssh/id_ed25519"                          "PRIVATE"
mk "$REPO/dotfiles/.gnupg/secring.gpg"                       "PRIVATE"
mk "$REPO/dotfiles/.local/state/noctalia/settings.toml"      "snapshot"
mk "$REPO/dotfiles/.config/linked.conf"                      "should not be written"

# Existing state on the "new" machine.
mk "$H/.gitconfig"                                           "[user] name = local"
mk "$H/.config/app/same.conf"                                "identical"
mk "$TMP/elsewhere"                                          "managed elsewhere"
mkdir -p "$H/.config"
ln -s "$TMP/elsewhere" "$H/.config/linked.conf"

run() { HOME="$H" STOA_DIR="$REPO" bash "$SCRIPT" "$@" </dev/null 2>&1; }

snapshot() { (cd "$H" && find . \( -type f -o -type l \) | sort | xargs -r -d '\n' stat -c '%n %s %Y' 2>/dev/null; cat "$H/.gitconfig"); }

# R1 / R2 — nothing changes
before=$(snapshot)
out=$(run --dry-run);       [ "$(snapshot)" = "$before" ] || fail "R1 dry run wrote something"
out2=$(run);                [ "$(snapshot)" = "$before" ] || fail "R2 non-tty run without --yes wrote something"
echo "$out"  | grep -q 'would be restored' || fail "R1 dry run did not report" "$out"
echo "$out2" | grep -q 'listed only'       || fail "R2 non-tty run did not say it only listed" "$out2"

# R3 / R4 / R5 / R6 / R9 — the real run
run --yes >/dev/null
[ "$(cat "$H/.zshrc" 2>/dev/null)" = "export FROM=repo" ]            || fail "R3 new file not restored"
[ "$(cat "$H/.config/my app/with space.conf" 2>/dev/null)" = "spaces ok" ] || fail "R9 path with spaces not restored"
[ "$(stat -c %a "$H/.ssh/config" 2>/dev/null)" = "600" ]             || fail "R3 file mode not preserved on .ssh/config" "got: $(stat -c %a "$H/.ssh/config" 2>/dev/null)"
[ "$(cat "$H/.gitconfig")" = "[user] name = repo" ]                  || fail "R4 differing file not replaced"
bak=$(ls "$H"/.gitconfig.bak.* 2>/dev/null | head -1)
[ -n "$bak" ] && [ "$(cat "$bak")" = "[user] name = local" ]         || fail "R4 backup missing or has the wrong content" "bak: ${bak:-none}"
ls "$H"/.config/app/same.conf.bak.* >/dev/null 2>&1                  && fail "R5 identical file was backed up"
[ ! -e "$H/.ssh/id_ed25519" ]                                        || fail "R6 private key was restored"
[ ! -e "$H/.gnupg/secring.gpg" ]                                     || fail "R6 .gnupg was restored"
[ ! -e "$H/.local/state/noctalia/settings.toml" ]                    || fail "R6 Noctalia snapshot was restored"
[ -L "$H/.config/linked.conf" ] && [ "$(cat "$TMP/elsewhere")" = "managed elsewhere" ] \
                                                                      || fail "R6 a symlink destination was overwritten"

# R7 — idempotent
after=$(snapshot)
out=$(run --yes)
[ "$(snapshot)" = "$after" ]                                         || fail "R7 second run changed files"
echo "$out" | grep -q 'Nothing to restore'                           || fail "R7 second run did not report nothing to do" "$out"
[ "$(ls "$H"/.gitconfig.bak.* 2>/dev/null | wc -l)" -eq 1 ]          || fail "R7 second run made another backup"

# R8 — no dotfiles/ at all
rm -rf "$REPO/dotfiles"
out=$(run --yes); rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q 'nothing to restore'       || fail "R8 missing dotfiles/ was treated as an error" "rc=$rc" "$out"

# --help and bad options
HOME="$H" bash "$SCRIPT" --help | grep -q 'RESUMO RÁPIDO'           || fail "--help has no quick summary"
HOME="$H" STOA_DIR="$REPO" bash "$SCRIPT" --bogus >/dev/null 2>&1; [ $? -eq 2 ] \
                                                                      || fail "an unknown option should exit 2"

if [ "$fails" -eq 0 ]; then
    echo "stoa-restore: ok"
    exit 0
fi
echo "$fails stoa-restore check(s) failed."
exit 1
