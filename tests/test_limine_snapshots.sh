#!/bin/bash
# Behavioural test for setup/enable-limine-snapshots.sh preflight.
#
# The script rewrites the boot configuration, so the property that matters
# most is that it changes nothing until every precondition holds and the
# user said yes. Every system command it reads is stubbed; `sudo` is a
# stub that records its call and fails, so any privileged step reached is
# visible. Properties:
#
#   L1  a non-Btrfs root is refused, before any sudo
#   L2  booted into a snapshot (subvol under .snapshots) is refused
#   L3  no Limine installed is refused
#   L4  no FAT32 boot partition at /efi, /boot or /boot/efi is refused
#   L5  less than 1 GiB free on the boot partition is refused
#   L6  everything fine but the user answers "n": exits 0, no sudo
#   L7  service already enabled (CachyOS preconfigures it): exits 0, no sudo
#   L8  running as root is refused

cd "$(dirname "$0")/.." || exit 1

SCRIPT="$PWD/setup/enable-limine-snapshots.sh"
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; mkdir -p "$BIN"
SUDO_LOG="$TMP/sudo.log"

_stub() { # <name> <body>
    printf '#!/bin/bash\n%s\n' "$2" > "$BIN/$1"; chmod +x "$BIN/$1"
}
_stub id        'if [ "$1" = "-u" ]; then echo "${FAKE_UID:-1000}"; else /usr/bin/id "$@"; fi'
_stub sudo      'echo "sudo $*" >> "$SUDO_LOG"; exit 99'
_stub systemctl '[ "$1 $2" = "is-enabled limine-snapper-sync.service" ] && [ "${FAKE_LSS_ENABLED:-no}" = yes ]'
_stub pacman    '[ "$1" = "-Qq" ] && [ "$2" = limine ] && [ "${FAKE_LIMINE:-yes}" = yes ]'
_stub mkinitcpio 'exit 0'
_stub findmnt   '
case "$*" in
    "-no FSTYPE /")       echo "${FAKE_ROOT_FS:-btrfs}" ;;
    "-no OPTIONS /")      echo "${FAKE_ROOT_OPTS:-rw,relatime,subvol=/@}" ;;
    "-no FSTYPE /boot")   echo "${FAKE_BOOT_FS:-vfat}" ;;
    *)                    exit 1 ;;
esac'
_stub df '
printf "Filesystem 1048576-blocks Used Available Capacity Mounted on\n"
printf "/dev/x %s 100 %s 10%% /boot\n" "${FAKE_ESP_SIZE:-4096}" "${FAKE_ESP_FREE:-3000}"'

MKCONF="$TMP/mkinitcpio.conf"
echo 'HOOKS=(base udev autodetect modconf block filesystems fsck)' > "$MKCONF"

FAILS=0
# _case <name> <want-rc> <want-text> [VAR=val ...] — answers "n" to prompts
_case() {
    local name="$1" want_rc="$2" want_text="$3"; shift 3
    : > "$SUDO_LOG"
    local out rc
    out=$(echo n | env PATH="$BIN:/usr/bin:/bin" SUDO_LOG="$SUDO_LOG" \
        MKINITCPIO_CONF="$MKCONF" "$@" bash "$SCRIPT" 2>&1); rc=$?
    if [ "$rc" -ne "$want_rc" ]; then
        echo "FAIL $name: exit $rc, want $want_rc"; echo "$out" | tail -n3 | sed 's/^/   /'
        FAILS=$((FAILS + 1)); return
    fi
    if ! printf '%s' "$out" | grep -q -- "$want_text"; then
        echo "FAIL $name: output lacks '$want_text'"; echo "$out" | tail -n3 | sed 's/^/   /'
        FAILS=$((FAILS + 1)); return
    fi
    if [ -s "$SUDO_LOG" ]; then
        echo "FAIL $name: reached sudo: $(head -n1 "$SUDO_LOG")"; FAILS=$((FAILS + 1))
    fi
}

_case "L1 ext4 root"          1 "not Btrfs"                FAKE_ROOT_FS=ext4
_case "L2 booted snapshot"    1 "booted into a snapshot"   FAKE_ROOT_OPTS="rw,subvol=/@/.snapshots/12/snapshot"
_case "L3 no limine"          1 "Limine is not installed"  FAKE_LIMINE=no
_case "L4 no FAT32 ESP"       1 "No FAT32 boot partition"  FAKE_BOOT_FS=ext4
_case "L5 ESP almost full"    1 "needs at least 1 GiB"     FAKE_ESP_FREE=200
_case "L6 user says no"       0 "Nothing was changed"
_case "L7 already enabled"    0 "nothing to do"            FAKE_LSS_ENABLED=yes
_case "L8 run as root"        1 "Do not run as root"       FAKE_UID=0

[ "$FAILS" -eq 0 ] || { echo "$FAILS check(s) failed"; exit 1; }
echo "enable-limine-snapshots: all checks passed"
