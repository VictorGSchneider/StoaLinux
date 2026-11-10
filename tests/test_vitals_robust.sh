#!/bin/bash
# stoa-vitals-status is polled by the health pill every 30 seconds. Two
# things about that poll, both found on a real machine:
#
# 1. A FAILING nvidia-smi BREAKS THE WHOLE DOCUMENT.
#    nvidia-smi reports its own failures on stdout, not stderr. After a
#    driver update and before the reboot it answers
#        Failed to initialize NVML: Driver/library version mismatch
#    and exits 18; the script pasted that into the JSON as the temperature:
#        "gpu":{"tempC":Failed to initialize NVML: Driver/library version mismatch}
#    The widget cannot decode it, so every reading on the pill goes stale —
#    for as long as the dGPU is awake, on every rolling-release update.
#
# 2. EVERY POLL RUNS A FULL PACKAGE-DATABASE SYNC.
#    `checkupdates` is a `pacman -Sy` against the mirrors. Called on each
#    poll, with the shell killing the script after about five seconds, each
#    kill left a download-XXXXXX directory behind in /tmp/checkup-db-<uid>:
#    161 of them, 751 MB of tmpfs, 71 minutes after boot. The count of
#    pending updates does not change from one half-minute to the next; it
#    has to be cached, not fetched.
#
#   R1  with nvidia-smi failing, the output is still valid JSON
#   R2  …and gpu.tempC is a number
#   R3  two polls in a row start checkupdates at most once between them
#
# Hermetic, unlike test_vitals_status.sh: checkupdates, nvidia-smi, sensors,
# systemctl, crontab and the slow hardware probes (busctl, journalctl,
# lspci) are stubs, so nothing here touches the network or wakes a GPU.
# `cat` is wrapped to report every PCI device as awake — otherwise a laptop
# whose dGPU happens to be suspended would skip the nvidia-smi branch and
# pass R1 without testing it.

cd "$(dirname "$0")/.." || exit 1
command -v jq >/dev/null || { echo "jq missing — skipped"; exit 0; }

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/config/stoa" "$TMP/cache"
FAILS=0
_check() { # <name> <expected> <actual>
    if [ "$2" = "$3" ]; then printf '  ✓ %s\n' "$1"
    else printf '  ✗ %s: expected [%s], got [%s]\n' "$1" "$2" "$3"; FAILS=$((FAILS + 1)); fi
}

REAL_CAT=$(command -v cat)
cat > "$TMP/bin/cat" <<STUB
#!/bin/sh
case "\$1" in */power/runtime_status) echo active; exit 0 ;; esac
exec "$REAL_CAT" "\$@"
STUB
cat > "$TMP/bin/nvidia-smi" <<'STUB'
#!/bin/sh
echo "Failed to initialize NVML: Driver/library version mismatch"
echo "NVML library version: 620.70"
exit 18
STUB
cat > "$TMP/bin/checkupdates" <<'STUB'
#!/bin/sh
echo run >> "$STUB_LOG"
exit 2
STUB
cat > "$TMP/bin/systemctl" <<'STUB'
#!/bin/sh
case "$*" in --failed*) exit 0 ;; esac
exit 1
STUB
for c in sensors crontab busctl journalctl lspci; do
    printf '#!/bin/sh\nexit 1\n' > "$TMP/bin/$c"
done
chmod +x "$TMP/bin/"*

printf '[OK]   a\n' > "$TMP/config/stoa/doctor.log"

_poll() {
    env PATH="$TMP/bin:$PATH" XDG_CONFIG_HOME="$TMP/config" XDG_CACHE_HOME="$TMP/cache" \
        STUB_LOG="$TMP/checkupdates.log" \
        bash scripts/health/stoa-vitals-status 2>/dev/null
}

out=$(_poll)
_check "R1 valid JSON while nvidia-smi fails" "valid" \
    "$(printf '%s' "$out" | jq -e . >/dev/null 2>&1 && echo valid || echo INVALID)"
[ "$FAILS" -eq 0 ] || printf '        %s\n' "$(printf '%s' "$out" | grep -o '"gpu":{[^}]*}')"
_check "R2 gpu.tempC is a number" "number" \
    "$(printf '%s' "$out" | jq -r '.gpu.tempC | type' 2>/dev/null || echo INVALID)"

_poll > /dev/null
_check "R3 two polls, at most one database sync" "yes" \
    "$([ "$(grep -c run "$TMP/checkupdates.log" 2>/dev/null)" -le 1 ] && echo yes \
        || echo "no ($(grep -c run "$TMP/checkupdates.log") syncs)")"

[ "$FAILS" -eq 0 ] || { echo "$FAILS check(s) failed"; exit 1; }
echo "vitals-robust: all checks passed"
