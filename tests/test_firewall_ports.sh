#!/bin/bash
# stoa-firewall must read the protocol of a listening socket correctly.
#
# `ss -tlnpH` prints no protocol column — the first field is the socket
# STATE:
#
#     LISTEN 0  4096  0.0.0.0:8080  0.0.0.0:*  users:(("python3",pid=4242,fd=3))
#
# The script took that first field as the protocol, so every port was
# "LISTEN" or "UNCONN", never tcp or udp. Nothing matched the whitelist
# ("8080/tcp"), and the port monitor's Allow button ran
# `stoa-firewall allow 8080 LISTEN`, which its own validation refuses:
#
#     stoa-firewall[1175]: Invalid protocol: 'LISTEN' (expected tcp or udp).
#
# (that line is from a real journal). The same parse is copied into
# stoa-settings' port list, where it made "tap to toggle" a no-op.
#
#   P1  `ports` names the protocol of a TCP listener as tcp
#   P2  …and shows a whitelisted TCP port as ALLOWED
#   P3  a TCP port that is not whitelisted stays BLOCKED
#   P4  a whitelisted UDP port is udp and ALLOWED
#   P5  process name and PID are still parsed
#   M1  the monitor's Allow action ends with the port in the whitelist
#
# ss, notify-send and sudo are stubs: ss answers with fixed sockets,
# notify-send "clicks" Allow, sudo/pkexec record and run nothing. No rule is
# loaded and no real socket is inspected.

cd "$(dirname "$0")/.." || exit 1

TMP=$(mktemp -d) || exit 1
MON_PID=""
# The monitor is a loop that never ends by itself. It has to be gone before
# the stubs are deleted: with $TMP/bin missing from its PATH the next lap
# would reach the real ss, notify-send and sudo.
_stop_monitor() {
    [ -n "$MON_PID" ] || return 0
    kill "$MON_PID" 2>/dev/null
    wait "$MON_PID" 2>/dev/null
    MON_PID=""
}
trap '_stop_monitor; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/config/stoa/firewall"
FAILS=0
_check() { # <name> <expected> <actual>
    if [ "$2" = "$3" ]; then printf '  ✓ %s\n' "$1"
    else printf '  ✗ %s: expected [%s], got [%s]\n' "$1" "$2" "$3"; FAILS=$((FAILS + 1)); fi
}

cat > "$TMP/bin/ss" <<'STUB'
#!/bin/sh
case "$*" in
    *t*l*|*-tl*)
        echo 'LISTEN 0      4096         0.0.0.0:8080       0.0.0.0:*    users:(("python3",pid=4242,fd=3))'
        echo 'LISTEN 0      128             [::]:22            [::]:*    users:(("sshd",pid=900,fd=4))'
        [ -e "$STUB_PHASE2" ] && \
        echo 'LISTEN 0      4096         0.0.0.0:9090       0.0.0.0:*    users:(("node",pid=5151,fd=20))'
        ;;
    *)
        echo 'UNCONN 0      0            0.0.0.0:5353       0.0.0.0:*    users:(("avahi-daemon",pid=700,fd=12))'
        ;;
esac
exit 0
STUB
# The monitor asks with `notify-send -A allow=Allow -A deny=Deny …` and
# reads the chosen action from stdout.
cat > "$TMP/bin/notify-send" <<'STUB'
#!/bin/sh
case "$*" in *allow=Allow*) echo allow ;; esac
exit 0
STUB
# No cached sudo (`sudo -n true` fails), so every privileged call goes to
# pkexec — one password box each. Only the first words are logged: a
# privileged call is a multi-line script and must stay one log line.
printf '#!/bin/sh\n[ "$*" = "-n true" ] && exit 1\nexit 0\n' > "$TMP/bin/sudo"
printf '#!/bin/sh\necho "pkexec $1 $2" >> "$STUB_LOG"\nexit 0\n' > "$TMP/bin/pkexec"
chmod +x "$TMP/bin/"*

WL="$TMP/config/stoa/firewall/allowed-ports.conf"
printf '8080/tcp\n5353/udp\n' > "$WL"

_fw() {
    env PATH="$TMP/bin:$PATH" XDG_CONFIG_HOME="$TMP/config" STUB_LOG="$TMP/sudo.log" \
        STUB_PHASE2="$TMP/phase2" bash scripts/system/stoa-firewall.sh "$@" 2>&1
}
# One port's row with the colour codes removed: "port proto STATE pid process"
_row() { _fw ports | sed 's/\x1b\[[0-9;]*m//g' | awk -v p="$1" '$1 == p { print $1, $2, $3, $4, $5; exit }'; }

row=$(_row 8080)
_check "P1 a TCP listener is tcp"                 "tcp"     "$(echo "$row" | awk '{print $2}')"
_check "P2 whitelisted TCP port shows ALLOWED"    "ALLOWED" "$(echo "$row" | awk '{print $3}')"
_check "P5 PID and process are parsed"            "4242 python3" "$(echo "$row" | awk '{print $4, $5}')"
_check "P3 other TCP port stays BLOCKED"          "tcp BLOCKED"  "$(_row 22 | awk '{print $2, $3}')"
_check "P4 whitelisted UDP port is udp, ALLOWED"  "udp ALLOWED"  "$(_row 5353 | awk '{print $2, $3}')"

# The monitor snapshots what is listening, then looks again every five
# seconds. 9090 appears after the snapshot; the stub clicks Allow. Started
# directly (not through _fw) so that $! is the process to stop, and under
# `timeout` so that it cannot outlive this test even if that is missed.
timeout 30 env PATH="$TMP/bin:$PATH" XDG_CONFIG_HOME="$TMP/config" STUB_LOG="$TMP/sudo.log" \
    STUB_PHASE2="$TMP/phase2" bash scripts/system/stoa-firewall.sh monitor \
    > "$TMP/monitor.out" 2>&1 &
MON_PID=$!
sleep 1; touch "$TMP/phase2"
for _ in $(seq 1 24); do grep -q '^9090/' "$WL" && break; sleep 0.5; done
_stop_monitor
_check "M1 Allow from the monitor whitelists the port" "9090/tcp" "$(grep '^9090/' "$WL")"
grep -m1 'Invalid' "$TMP/monitor.out" | sed 's/\x1b\[[0-9;]*m//g; s/^ */        /'

# Password boxes. Every privileged call that cannot use a cached sudo is one
# pkexec prompt, so allowing a port must be ONE call, whatever it does inside,
# and merely looking at the status must be none.
_priv_calls() { grep -c '^pkexec' "$TMP/sudo.log" 2>/dev/null || true; }
: > "$TMP/sudo.log"; _fw allow 7777 tcp > /dev/null
_check "B1 allow is one privileged call"        "1" "$(_priv_calls)"
: > "$TMP/sudo.log"; _fw deny 7777 tcp > /dev/null
_check "B2 deny is one privileged call"         "1" "$(_priv_calls)"
: > "$TMP/sudo.log"; _fw enable > /dev/null
_check "B3 enable is one privileged call"       "1" "$(_priv_calls)"
: > "$TMP/sudo.log"; _fw disable > /dev/null
_check "B4 disable is one privileged call"      "1" "$(_priv_calls)"
: > "$TMP/sudo.log"; _fw setup > /dev/null
_check "B5 setup is one privileged call"        "1" "$(_priv_calls)"
: > "$TMP/sudo.log"; _fw status > /dev/null; _fw active > /dev/null
_check "B6 status/active never ask for root"    "0" "$(_priv_calls)"

[ "$FAILS" -eq 0 ] || { echo "$FAILS check(s) failed"; exit 1; }
echo "firewall-ports: all checks passed"
