#!/bin/bash
# The Maintenance buttons of the health panel (stoa-health update-*, cleanup-user,
# schedule, unschedule).
#
# Anything that needs root has to run in a terminal: from the widget there is
# nothing to answer sudo, every prompt-less sudo is a failed login to
# pam_faillock, and three lock the account out. Run in the background, yay's
# own sudo calls did exactly that.
#
#   M1-M5  update-system / update-aur / update-all go through the terminal, in
#          the right order, and the AUR step never runs after a failed pacman
#          or without yay
#   M6     cleanup-user needs no sudo, so it does NOT open a terminal
#   M7     schedule goes through the terminal
#   U1-U5  unschedule removes the root timer, the user timer and the crontab
#          line wherever they are — and only the cleanup line, not the rest
#
# Everything is stubbed. sudo never executes anything but the fake pacman, and
# PATH holds no real pacman/yay/systemctl/crontab, so nothing here can touch
# the machine running the test.
cd "$(dirname "$0")/.." || exit 1

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
H="$TMP/home"; STUBS="$TMP/stubs"; SYS="$TMP/sys"; LOG="$TMP/calls.log"
mkdir -p "$H/.local/bin" "$H/.config/stoa" "$STUBS" "$SYS"
FAILS=0
_check() { # <name> <expected> <actual>
    if [ "$2" = "$3" ]; then printf '  ✓ %s\n' "$1"
    else printf '  ✗ %s: expected [%s], got [%s]\n' "$1" "$2" "$3"; FAILS=$((FAILS + 1)); fi
}

# System tools, minus every one a stub stands in for.
for f in /usr/bin/*; do
    case "${f##*/}" in sudo|pacman|yay|systemctl|crontab|kitty) continue ;; esac
    ln -s "$f" "$SYS/${f##*/}"
done

_stub() { printf '#!/bin/bash\n%s\n' "$2" > "$STUBS/$1"; chmod +x "$STUBS/$1"; }
_stub pacman  'echo "pacman $*" >> "$STUB_LOG"; exit "${PACMAN_RC:-0}"'
_stub yay     'echo "yay $*" >> "$STUB_LOG"'
# sudo: only the fake pacman is ever run; everything else is just recorded.
_stub sudo    'echo "sudo $*" >> "$STUB_LOG"; [ "$1" = pacman ] && exec "$STUBS_DIR/pacman" "${@:2}"; exit 0'
_stub systemctl '
echo "systemctl $*" >> "$STUB_LOG"
case "$*" in
    "--user is-enabled "*) [ -e "$STUB_STATE/user_timer" ] ;;
    "is-enabled "*)        [ -e "$STUB_STATE/root_timer" ] ;;
    *) exit 0 ;;
esac'
_stub crontab '
if [ "$1" = "-l" ]; then [ -s "$STUB_STATE/cron" ] && cat "$STUB_STATE/cron"; exit 0; fi
# Read everything before writing: in `crontab -l | grep | crontab -` both ends
# start at once, and the real crontab does not truncate under the reader.
data=$(cat); printf "%s\n" "$data" > "$STUB_STATE/cron"'
cat > "$H/.local/bin/stoa-maintain" <<'STUB'
#!/bin/bash
echo "maintain $*" >> "$STUB_LOG"
STUB
# The terminal: remember the title, run what it is handed.
cat > "$TMP/term" <<'STUB'
#!/bin/bash
echo "$2" >> "$STUB_TITLES"
shift 3
"$@" < /dev/null
STUB
chmod +x "$H/.local/bin/stoa-maintain" "$TMP/term"

_health() { # <args...>; waits for the backgrounded terminal to finish
    : > "$LOG"; : > "$TMP/titles"
    env -i PATH="$STUBS:$SYS" HOME="$H" XDG_CONFIG_HOME="$H/.config" TERMINAL="$TMP/term" \
        STUB_LOG="$LOG" STUB_TITLES="$TMP/titles" STUB_STATE="$TMP/state" STUBS_DIR="$STUBS" \
        PACMAN_RC="${PACMAN_RC:-0}" \
        bash scripts/health/stoa-health.sh "$@" < /dev/null > "$TMP/out" 2>&1
    local i
    for i in $(seq 1 40); do
        pgrep -f "$TMP/term" > /dev/null || break
        sleep 0.1
    done
    sleep 0.2
}
_calls() { tr '\n' ';' < "$LOG" | sed 's/;$//'; }
mkdir -p "$TMP/state"

# ── updates ──
_health update-system
_check "M1 update-system"           "sudo pacman -Syu --noconfirm;pacman -Syu --noconfirm" "$(_calls)"
_check "M1 opened a terminal"       "Stoa — Update system" "$(cat "$TMP/titles")"

_health update-aur
_check "M2 update-aur"              "yay -Syu --noconfirm" "$(_calls)"

_health update-all
_check "M3 update-all order"        "sudo pacman -Syu --noconfirm;pacman -Syu --noconfirm;yay -Sua --noconfirm" "$(_calls)"

PACMAN_RC=1 _health update-all
_check "M4 no AUR after failed pacman" "sudo pacman -Syu --noconfirm;pacman -Syu --noconfirm" "$(_calls)"

rm -f "$STUBS/yay"
_health update-all
_check "M5 update-all without yay"  "sudo pacman -Syu --noconfirm;pacman -Syu --noconfirm" "$(_calls)"
_health update-aur
_check "M5 update-aur without yay"  "" "$(_calls)"

# ── cleanup / schedule ──
_health cleanup-user
_check "M6 cleanup-user"            "maintain --cleanup --user" "$(_calls)"
_check "M6 no terminal for it"      "" "$(cat "$TMP/titles")"
_health schedule
_check "M7 schedule"                "maintain --schedule" "$(_calls)"
_check "M7 in a terminal"           "Stoa — Schedule cleanup" "$(cat "$TMP/titles")"

# ── unschedule ──
_health unschedule-run
_check "U1 nothing scheduled"       "No boot cleanup schedule found." "$(cat "$TMP/out")"
_check "U1 asked for no sudo"       "" "$(grep -c '^sudo' "$LOG" | grep -v '^0$')"

touch "$TMP/state/root_timer"
_health unschedule-run
_check "U2 root timer disabled"     "1" "$(grep -c '^sudo systemctl disable --now stoa-maintain-cleanup.timer' "$LOG")"
_check "U2 root units removed"      "1" "$(grep -c '^sudo rm -f /etc/systemd/system/stoa-maintain-cleanup.service' "$LOG")"
rm -f "$TMP/state/root_timer"

mkdir -p "$H/.config/systemd/user"
touch "$H/.config/systemd/user/stoa-maintain-cleanup.timer" "$H/.config/systemd/user/stoa-maintain-cleanup.service"
touch "$TMP/state/user_timer"
_health unschedule-run
_check "U3 user units removed"      "gone" "$([ -e "$H/.config/systemd/user/stoa-maintain-cleanup.timer" ] || echo gone)"
_check "U3 user timer disabled"     "1" "$(grep -c '^systemctl --user disable --now stoa-maintain-cleanup.timer' "$LOG")"
_check "U3 no sudo for a user timer" "" "$(grep -c '^sudo' "$LOG" | grep -v '^0$')"
rm -f "$TMP/state/user_timer"

printf '%s\n' '@daily bash /x/scripts/system/stoa-maintain.sh --cleanup --user' \
              '0 3 * * * /x/stoa-maintain --backup' \
              '* * * * * echo keep-me' \
              '@reboot bash /x/BRCS.sh --cleanup' > "$TMP/state/cron"
_health unschedule-run
_check "U4 only cleanup lines go"   "0 3 * * * /x/stoa-maintain --backup|* * * * * echo keep-me" \
    "$(paste -sd'|' "$TMP/state/cron")"

[ "$FAILS" -eq 0 ] || { echo "$FAILS check(s) failed"; exit 1; }
echo "health-maintenance: all checks passed"
