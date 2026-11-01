#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — greetd pre-start guard                         ║
# ║  "Only what serves, stays."                                  ║
# ║                                                              ║
# ║  Installed to /usr/local/lib/stoa/greetd-prestart and run as ║
# ║  greetd's ExecStartPre by setup/enable-stoa-greetd.sh.       ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Two jobs, both about the GPU the greeter's compositor is about to take.
#
# 1. WAIT FOR PLYMOUTH TO LET GO.
#    `plymouth quit` returns before plymouthd has exited, and plymouthd keeps
#    DRM master on the panel's GPU until it does. greetd is ordered after
#    plymouth-quit-wait, so it started ~20 ms after the quit — and when
#    plymouthd outlived that, the greeter's compositor died with
#
#      [libseat] Could not take device: Device or resource busy
#      Failed to open device: '/dev/dri/cardN': Device or resource busy
#
#    greetd then logs "greeter exited without creating a session" and does
#    not retry: a black screen until the power button. It was intermittent
#    because it is a race. We hold greetd back until plymouthd is gone and
#    nothing but systemd/logind holds a card (bounded, ~5 s).
#
# 2. PIN THE COMPOSITOR TO THE PANEL'S GPU.
#    On a hybrid laptop the greeter's wlroots compositor otherwise picks both
#    cards and builds a multi-GPU renderer whose buffer modifiers the panel
#    cannot scan out (see enable-stoa-greetd.sh). The card is resolved HERE,
#    at every start, from the connected eDP connector: cardN numbering
#    changes with module load order (it changed when NVIDIA left the
#    initramfs), so a number written at install time goes stale. The result
#    goes to an EnvironmentFile that greetd.service reads after this runs.
#
# CachyOS's GPU configuration outranks ours: if the greetd unit already sets
# WLR_DRM_DEVICES (a distro or admin drop-in), we do not pin anything.
#
# It always exits 0: a hiccup here must never stop the login screen.
# Everything it saw is logged under the tag `stoa-greetd-prestart`:
#   journalctl -b -t stoa-greetd-prestart

DRI_DEV="${STOA_DRI_DEV:-/dev/dri}"
DRM_SYSFS="${STOA_DRM_SYSFS:-/sys/class/drm}"
PROC="${STOA_PROC:-/proc}"
ENV_FILE="${STOA_GREETD_ENV:-/run/stoa/greetd-gpu.env}"
TICKS="${STOA_WAIT_TICKS:-25}"      # x STEP = the longest we will hold greetd
STEP="${STOA_WAIT_STEP:-0.2}"

_log() { logger -t stoa-greetd-prestart -- "$*" 2>/dev/null || true; }

# PID:comm of every process holding a card, except systemd and logind (which
# always do, and are not what we are waiting for).
_holders() {
    local pid comm
    fuser "$DRI_DEV"/card[0-9]* 2>/dev/null | tr -s ' ' '\n' | grep -E '^[0-9]+$' | sort -u |
    while read -r pid; do
        comm=$(cat "$PROC/$pid/comm" 2>/dev/null)
        case "$comm" in
            systemd|systemd-logind|"") ;;
            *) echo "$pid:$comm" ;;
        esac
    done | tr '\n' ' '
}

_plymouthd() { pgrep -x plymouthd 2>/dev/null | tr '\n' ' '; }

# The card that owns a connected eDP connector, as a path under $DRI_DEV.
_panel_card() {
    local conn card
    for conn in "$DRM_SYSFS"/card*-eDP-*; do
        [ -e "$conn/status" ] || continue
        [ "$(cat "$conn/status" 2>/dev/null)" = "connected" ] || continue
        card="${conn##*/}"          # card1-eDP-1
        card="${card%%-*}"          # card1
        [ -e "$DRI_DEV/$card" ] && { echo "$DRI_DEV/$card"; return 0; }
    done
    return 1
}

# ── 1. wait ──────────────────────────────────────────────────────────
_log "start: plymouthd=[$(_plymouthd)] holders=[$(_holders)]"
i=0
while [ "$i" -lt "$TICKS" ]; do
    [ -z "$(pgrep -x plymouthd 2>/dev/null)" ] && [ -z "$(_holders)" ] && break
    sleep "$STEP"
    i=$((i + 1))
done
if [ "$i" -ge "$TICKS" ]; then
    _log "gave up after ${i} polls: plymouthd=[$(_plymouthd)] holders=[$(_holders)]"
else
    _log "clear after ${i} polls (step ${STEP}s)"
fi

# ── 2. pin ───────────────────────────────────────────────────────────
mkdir -p "$(dirname "$ENV_FILE")" 2>/dev/null
cards=("$DRI_DEV"/card[0-9]*)
if systemctl show greetd.service -p Environment --value 2>/dev/null | grep -q 'WLR_DRM_DEVICES='; then
    rm -f "$ENV_FILE"
    _log "not pinning: greetd.service already sets WLR_DRM_DEVICES (someone else's choice wins)"
elif [ "${#cards[@]}" -ge 2 ] && node=$(_panel_card); then
    printf 'WLR_DRM_DEVICES=%s\nWLR_NO_HARDWARE_CURSORS=1\n' "$node" > "$ENV_FILE"
    _log "pinned the greeter to ${node} (panel's GPU, ${#cards[@]} cards present)"
else
    # Single GPU, or no connected eDP: nothing to pin, and a stale file from
    # an earlier boot must not outlive the hardware that justified it.
    rm -f "$ENV_FILE"
    _log "not pinning (${#cards[@]} card(s), no multi-GPU panel found)"
fi
exit 0
