#!/bin/bash
# Behavioural test for _unseed_profile in the two login-flow scripts.
#
# Both enable-stoa-greeter.sh and enable-stoa-greetd.sh carry their own copy
# of this function (the greetd one says so: "Must stay in sync with
# enable-stoa-greeter.sh's copy"), and both of them edit ~/.zprofile and
# ~/.bash_profile in place. Getting it wrong does not fail loudly — it
# silently eats whatever the user keeps in their login profile.
#
# The trap it fell into: `sed '/start/,/end/d'` on a profile that has the
# start marker but no end marker is a range that never closes, and sed then
# deletes from the marker to end of file. Profiles seeded by older releases
# use exactly that shape — a marker plus a single line, no end marker — so
# the block delete would take every line the user had written below it.
#
# Both forms are exercised against both copies, with user content on either
# side of the block, and the content has to survive.

cd "$(dirname "$0")/.." || exit 1

SCRIPTS=(setup/enable-stoa-greeter.sh setup/enable-stoa-greetd.sh)
HOOK="/home/u/StoaLinux/shell/stoa-autostart-hyprland.sh"
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

BEFORE='export PATH="$HOME/bin:$PATH"
export EDITOR=nvim'
AFTER='export JAVA_HOME=/usr/lib/jvm/default
alias ll='"'"'ls -la'"'"'
. ~/.work-env'

_fixture() {
    local form="$1" out="$2"
    {
        printf '%s\n\n' "$BEFORE"
        echo "# StoaLinux: autostart Hyprland on tty1"
        if [ "$form" = block ]; then
            echo "if [ -f \"${HOOK}\" ]; then"
            echo "    . \"${HOOK}\""
            echo "else"
            echo "    echo \"StoaLinux: ${HOOK} is missing —\" >&2"
            echo "fi"
            echo "# StoaLinux: end autostart Hyprland block"
        else
            echo "[ -f \"${HOOK}\" ] && . \"${HOOK}\""
        fi
        printf '\n%s\n' "$AFTER"
    } > "$out"
}

# Run one script's own copy of the function against one fixture.
_run_unseed() {
    local script="$1" rc="$2"
    {
        echo 'O=""; R=""'
        grep -E '^PROFILE_MARK(_END)?=' "$script"
        sed -n '/^_unseed_profile() {/,/^}/p' "$script"
        echo '_unseed_profile "$1"'
    } > "$TMP/harness.sh"
    bash "$TMP/harness.sh" "$rc" >/dev/null 2>&1
}

status=0
for script in "${SCRIPTS[@]}"; do
    for form in block legacy; do
        rc="$TMP/profile.$form"
        _fixture "$form" "$rc"
        _run_unseed "$script" "$rc"

        if grep -q 'stoa-autostart-hyprland' "$rc"; then
            echo "profile-unseed: $script ($form form): the Stoa block was not removed"
            status=1
        fi
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            if ! grep -qxF -- "$line" "$rc"; then
                echo "profile-unseed: $script ($form form): lost a user line from the" \
                     "profile: $line"
                status=1
            fi
        done < <(printf '%s\n%s\n' "$BEFORE" "$AFTER")
    done
done

if [ "$status" -eq 0 ]; then
    echo "profile-unseed: ok"
else
    echo "" >&2
    echo "Profiles must survive unseeding with everything but the Stoa block intact." >&2
fi
exit "$status"
