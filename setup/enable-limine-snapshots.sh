#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Boot into Btrfs snapshots from Limine          ║
# ║  "Begin at once to live, and count each separate day as a    ║
# ║   separate life." — Seneca                                   ║
# ║                                                              ║
# ║  Sets up limine-snapper-sync so every Snapper snapshot of /  ║
# ║  shows up in the Limine boot menu, and a broken update can   ║
# ║  be undone by booting yesterday's system.                    ║
# ║                                                              ║
# ║  Follows upstream's "easy setup":                            ║
# ║    1. snapper config for /                                   ║
# ║    2. limine-mkinitcpio-hook (or limine-dracut-support),     ║
# ║       which owns $ESP_PATH/limine.conf from then on          ║
# ║    3. btrfs-overlayfs initramfs hook, so a read-only         ║
# ║       snapshot boots into a writable overlay                 ║
# ║    4. limine-update, then limine-snapper-sync.service        ║
# ║                                                              ║
# ║  Checks everything before it changes anything; backs up      ║
# ║  every file it edits. Re-run safely. --disable stops the     ║
# ║  sync service (it never touches your boot entries).          ║
# ║                                                              ║
# ║  Upstream: https://gitlab.com/Zesko/limine-snapper-sync      ║
# ╚══════════════════════════════════════════════════════════════╝

set -e

STOA_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
MKINITCPIO_CONF="${MKINITCPIO_CONF:-/etc/mkinitcpio.conf}"

# Colors
B='\033[38;2;196;154;92m'
S='\033[38;2;110;106;98m'
F='\033[38;2;212;207;196m'
O='\033[38;2;138;154;108m'
T='\033[38;2;179;107;90m'
R='\033[0m'

_ok()   { echo -e "  ${O}[✓] $*${R}"; }
_skip() { echo -e "  ${S}[~] $*${R}"; }
_info() { echo -e "  ${F}$*${R}"; }
_die()  { echo -e "  ${T}[!] $*${R}" >&2; exit 1; }

# Everything privileged goes through sudo; AUR builds must not run as root.
if [ "$(id -u)" -eq 0 ]; then
    _die "Do not run as root. The script uses sudo when necessary."
fi

# ── --disable ──
if [ "${1:-}" = "--disable" ]; then
    if systemctl is-enabled limine-snapper-sync.service &>/dev/null; then
        sudo systemctl disable --now limine-snapper-sync.service
        _ok "limine-snapper-sync.service disabled. Existing snapshot entries stay in limine.conf until the next sync."
    else
        _skip "limine-snapper-sync.service is not enabled."
    fi
    exit 0
fi

echo ""
echo -e "  ${B}╔══════════════════════════════════════════════════════╗${R}"
echo -e "  ${B}║     STOA LINUX — Limine snapshot boot menu           ║${R}"
echo -e "  ${B}╚══════════════════════════════════════════════════════╝${R}"
echo ""

# Let this user list and create snapshots of / without a password, through
# snapper's own ALLOW_USERS (SYNC_ACL makes /.snapshots readable to them).
# This is what lets the "Create snapshot" button in the stoa-health panel
# work without a prompt. Asks first; no-op when already granted.
_grant_snapper_user() {
    local user="${USER:-$(id -un)}" cfg=/etc/snapper/configs/root
    [ -f "$cfg" ] || return 0
    if grep -qE "^ALLOW_USERS=\"([^\"]* )?${user}( [^\"]*)?\"" "$cfg" 2>/dev/null; then
        _skip "${user} may already create snapshots without a password."
        return 0
    fi
    read -rp "  Let ${user} create snapshots without a password (snapper ALLOW_USERS)? [Y/n]: " _allow
    case "${_allow,,}" in
        n|no) _skip "Not granted — creating a snapshot from the panel will ask for your password." ;;
        *)
            local current
            current=$(sed -nE 's/^ALLOW_USERS="(.*)"/\1/p' "$cfg" 2>/dev/null)
            sudo snapper -c root set-config "ALLOW_USERS=${current:+$current }${user}" "SYNC_ACL=yes"
            _ok "${user} may now list and create snapshots without a password"
            ;;
    esac
}

# ══════════════════════════════════════════════════════════════
# Preflight — nothing below changes the system
# ══════════════════════════════════════════════════════════════

# Already done (CachyOS ships this preconfigured when you pick Limine + Btrfs).
if systemctl is-enabled limine-snapper-sync.service &>/dev/null; then
    _ok "limine-snapper-sync is already set up and enabled."
    _grant_snapper_user
    _ok "Nothing else to do."
    exit 0
fi

# Root must be Btrfs, and not a snapshot we happen to have booted into.
ROOT_FSTYPE=$(findmnt -no FSTYPE / 2>/dev/null || true)
[ "$ROOT_FSTYPE" = "btrfs" ] || \
    _die "/ is ${ROOT_FSTYPE:-unknown}, not Btrfs. Snapshot booting needs a Btrfs root (pick Btrfs in archinstall's disk menu)."
ROOT_OPTS=$(findmnt -no OPTIONS / 2>/dev/null || true)
case "$ROOT_OPTS" in
    *subvol=*.snapshots*)
        _die "You are booted into a snapshot (${ROOT_OPTS}). Boot the normal system first." ;;
esac
_ok "Root is Btrfs"

# Limine must already be the bootloader.
command -v limine &>/dev/null || pacman -Qq limine &>/dev/null || \
    _die "Limine is not installed. This only works when Limine is your bootloader."
_ok "Limine is installed"

# The FAT32 boot partition: the first of the paths upstream searches that is
# a vfat mount.
ESP_PATH=""
for _p in /efi /boot /boot/efi; do
    if [ "$(findmnt -no FSTYPE "$_p" 2>/dev/null || true)" = "vfat" ]; then
        ESP_PATH="$_p"
        break
    fi
done
[ -n "$ESP_PATH" ] || \
    _die "No FAT32 boot partition mounted at /efi, /boot or /boot/efi."
_ok "Boot partition: ${ESP_PATH}"

# Size. Upstream recommends 4 GiB (every snapshot entry keeps its own kernel
# + initramfs on the ESP; NVIDIA/DKMS initramfs can pass 300 MiB each) and
# needs at least 1 GiB free to work at all.
ESP_SIZE_MB=$(df -Pm "$ESP_PATH" | awk 'NR==2{print $2}')
ESP_FREE_MB=$(df -Pm "$ESP_PATH" | awk 'NR==2{print $4}')
if [ "${ESP_FREE_MB:-0}" -lt 1024 ]; then
    _die "Only ${ESP_FREE_MB} MiB free on ${ESP_PATH}; limine-entry-tool needs at least 1 GiB free."
fi
if [ "${ESP_SIZE_MB:-0}" -lt 4000 ]; then
    echo -e "  ${T}[!] ${ESP_PATH} is ${ESP_SIZE_MB} MiB. Upstream recommends 4 GiB; with less,${R}"
    echo -e "  ${T}    only a few snapshots fit in the boot menu (older ones are dropped automatically).${R}"
else
    _ok "Boot partition size: ${ESP_SIZE_MB} MiB"
fi

# Initramfs generator decides which integration package to use.
if command -v mkinitcpio &>/dev/null && [ -f "$MKINITCPIO_CONF" ]; then
    INITRAMFS="mkinitcpio"
    HOOK_PKG="limine-mkinitcpio-hook"
elif command -v dracut &>/dev/null; then
    INITRAMFS="dracut"
    HOOK_PKG="limine-dracut-support"
else
    _die "Neither mkinitcpio nor dracut found — cannot pick an initramfs integration."
fi
_ok "Initramfs: ${INITRAMFS}"

# UEFI or BIOS: on BIOS, limine-entry-tool does not deploy the Limine binary.
if [ -d /sys/firmware/efi ]; then BOOT_MODE="UEFI"; else BOOT_MODE="BIOS"; fi
_ok "Firmware: ${BOOT_MODE}"

# ── Plan ──
echo ""
_info "This will:"
echo -e "  ${S}  • install snapper, btrfs-progs, inotify-tools (pacman)${R}"
echo -e "  ${S}  • install ${HOOK_PKG} and limine-snapper-sync (AUR)${R}"
echo -e "  ${S}  • create a Snapper config for / if there is none (and, if you agree, let you snapshot without a password)${R}"
echo -e "  ${S}  • write ESP_PATH=${ESP_PATH} to /etc/default/limine and, if missing, /etc/kernel/cmdline${R}"
[ "$INITRAMFS" = "mkinitcpio" ] && \
echo -e "  ${S}  • add the btrfs-overlayfs hook to ${MKINITCPIO_CONF}${R}"
echo -e "  ${S}  • regenerate ${ESP_PATH}/limine.conf with limine-update${R}"
[ "$BOOT_MODE" = "UEFI" ] && \
echo -e "  ${S}    (on UEFI this also installs Limine to EFI/limine/ and puts that entry first in the boot order)${R}"
echo -e "  ${S}  • move older limine.conf copies that would shadow it to *.stoa-bak-${STAMP}${R}"
echo -e "  ${S}  • take one snapshot and enable limine-snapper-sync.service${R}"
echo ""
echo -e "  ${T}  This rewrites your boot configuration. Keep an Arch ISO at hand; every file${R}"
echo -e "  ${T}  changed is backed up next to itself with the suffix .stoa-bak-${STAMP}.${R}"
echo ""
read -rp "  Continue? [y/N]: " _go
case "${_go,,}" in y|yes) ;; *) _skip "Cancelled. Nothing was changed."; exit 0 ;; esac

# ══════════════════════════════════════════════════════════════
# Changes
# ══════════════════════════════════════════════════════════════

_backup() { # <file> — sudo cp next to itself, once per run
    [ -e "$1" ] || return 0
    sudo cp -a "$1" "$1.stoa-bak-${STAMP}"
}

# ── 1. Packages (official repos) ──
echo ""
_info "Installing snapper, btrfs-progs, inotify-tools..."
sudo pacman -S --needed --noconfirm snapper btrfs-progs inotify-tools

read -rp "  Also install snap-pac (a snapshot before and after every pacman transaction)? [Y/n]: " _snap_pac
case "${_snap_pac,,}" in
    n|no) _skip "snap-pac skipped — only Snapper's timeline snapshots will appear." ;;
    *)    sudo pacman -S --needed --noconfirm snap-pac && _ok "snap-pac installed" ;;
esac

# ── 2. Snapper config for / ──
if sudo snapper -c root list &>/dev/null; then
    _skip "Snapper config 'root' already exists."
elif mountpoint -q /.snapshots; then
    # The archinstall/Arch wiki layout mounts a separate @.snapshots subvolume
    # at /.snapshots, and `snapper create-config` refuses an existing path.
    # The wiki's fix: let snapper create its subvolume, delete it, and
    # remount ours. Only safe while ours is empty — never delete snapshots.
    if [ -n "$(sudo ls -A /.snapshots 2>/dev/null)" ]; then
        _die "/.snapshots is a mounted subvolume that is not empty and has no Snapper config. Sort that out by hand (Arch wiki: Snapper#Configuration_of_snapper_and_mount_point)."
    fi
    _info "Creating Snapper config for / (separate /.snapshots subvolume)..."
    sudo umount /.snapshots
    sudo rmdir /.snapshots
    sudo snapper -c root create-config /
    sudo btrfs subvolume delete /.snapshots
    sudo mkdir /.snapshots
    sudo mount -a
    sudo chmod 750 /.snapshots
    _ok "Snapper config 'root' created on the existing /.snapshots subvolume"
else
    sudo snapper -c root create-config /
    _ok "Snapper config 'root' created"
fi
sudo systemctl enable --now snapper-cleanup.timer &>/dev/null || true
_grant_snapper_user

# ── 3. Kernel command line and ESP path for limine-entry-tool ──
if [ ! -s /etc/kernel/cmdline ]; then
    # From the running system — never from a snapshot (checked above). Drop
    # the boot-loader-provided bits limine-entry-tool fills in itself.
    _cmdline=$(sed -E 's/(^| )(BOOT_IMAGE|initrd)=[^ ]*//g; s/^ +//; s/ +$//' /proc/cmdline)
    [ -n "$_cmdline" ] || _die "Could not read the kernel command line from /proc/cmdline."
    sudo mkdir -p /etc/kernel
    echo "$_cmdline" | sudo tee /etc/kernel/cmdline >/dev/null
    _ok "/etc/kernel/cmdline: ${_cmdline}"
else
    _skip "/etc/kernel/cmdline already set."
fi

if sudo grep -qsE '^[[:space:]]*ESP_PATH=' /etc/default/limine; then
    _skip "ESP_PATH already set in /etc/default/limine."
else
    _backup /etc/default/limine
    echo "ESP_PATH=\"${ESP_PATH}\"" | sudo tee -a /etc/default/limine >/dev/null
    _ok "ESP_PATH=${ESP_PATH} written to /etc/default/limine"
fi

# ── 4. AUR packages ──
# shellcheck source=lib/aur.sh
source "${STOA_DIR}/setup/lib/aur.sh"
_install_aur "$HOOK_PKG"           "${HOOK_PKG}"
_install_aur limine-snapper-sync   "limine-snapper-sync"

# ── 5. btrfs-overlayfs initramfs hook (mkinitcpio) ──
# dracut users get the equivalent module from limine-dracut-support.
if [ "$INITRAMFS" = "mkinitcpio" ]; then
    _hooks_line=$(grep -E '^[[:space:]]*HOOKS=' "$MKINITCPIO_CONF" | tail -n1)
    case "$_hooks_line" in
        *btrfs-overlayfs*)
            _skip "mkinitcpio already has the btrfs-overlayfs hook." ;;
        *filesystems*)
            # systemd-based initramfs needs the sd- variant; the plain one
            # is incompatible there (upstream README).
            _ovl="btrfs-overlayfs"
            case " ${_hooks_line} " in *" systemd "*|*"(systemd "*) _ovl="sd-btrfs-overlayfs" ;; esac
            _backup "$MKINITCPIO_CONF"
            sudo sed -i -E "/^[[:space:]]*HOOKS=/ s/\bfilesystems\b/filesystems ${_ovl}/" "$MKINITCPIO_CONF"
            _ok "mkinitcpio HOOKS: added ${_ovl} after filesystems"
            ;;
        *)
            _die "Could not find 'filesystems' in HOOKS= of ${MKINITCPIO_CONF} — add btrfs-overlayfs after it by hand, then re-run." ;;
    esac
fi

# ── 6. Regenerate initramfs + $ESP_PATH/limine.conf ──
_info "Running limine-update (rebuilds initramfs and boot entries)..."
_backup "${ESP_PATH}/limine.conf"
sudo limine-update
NEW_CONF="${ESP_PATH}/limine.conf"
if ! sudo grep -qsE '^[[:space:]]*//' "$NEW_CONF"; then
    _die "limine-update did not produce kernel entries in ${NEW_CONF}. Older configs were left untouched; check the output above."
fi
_ok "${NEW_CONF} has kernel entries"

# On BIOS, limine-entry-tool does not deploy limine-bios.sys next to it.
if [ "$BOOT_MODE" = "BIOS" ] && [ ! -e "${ESP_PATH}/limine-bios.sys" ] \
    && [ ! -e "${ESP_PATH}/limine/limine-bios.sys" ] && [ ! -e "${ESP_PATH}/boot/limine/limine-bios.sys" ]; then
    echo -e "  ${T}[!] BIOS: limine-bios.sys not found on ${ESP_PATH}. See https://wiki.archlinux.org/title/Limine#BIOS_systems_with_MBR${R}"
fi

# ── 7. Get older configs out of Limine's search path ──
# Limine reads the first of: <EFI app dir>/limine.conf, /boot/limine/limine.conf,
# /boot/limine.conf, /limine/limine.conf, /limine.conf (partition-relative).
# limine-entry-tool writes the last one, and installs its EFI binary to
# EFI/limine/, so a config archinstall left at any earlier path wins and
# the snapshot menu never appears. EFI/BOOT/limine.conf is left alone: only
# the firmware's fallback loader reads it, and it keeps that path bootable.
for _old in \
    "${ESP_PATH}/EFI/limine/limine.conf" \
    "${ESP_PATH}/boot/limine/limine.conf" \
    "${ESP_PATH}/boot/limine.conf" \
    "${ESP_PATH}/limine/limine.conf"; do
    if sudo test -f "$_old"; then
        sudo mv "$_old" "${_old}.stoa-bak-${STAMP}"
        _ok "Moved shadowing $(basename "$(dirname "$_old")")/limine.conf → ${_old}.stoa-bak-${STAMP}"
    fi
done

# ── 8. First snapshot, first sync, enable ──
sudo snapper -c root create -d "stoa: limine-snapper-sync setup"
if sudo limine-snapper-sync; then
    _ok "limine-snapper-sync ran"
else
    _die "limine-snapper-sync failed — the service was NOT enabled. Check the output above."
fi
sudo systemctl enable --now limine-snapper-sync.service
_ok "limine-snapper-sync.service enabled"

echo ""
_info "Done. Reboot and look for the Snapshots submenu under your system in Limine."
echo -e "  ${S}  Restore from the running system:  limine-snapper-restore${R}"
echo -e "  ${S}  Undo this setup: restore the *.stoa-bak-${STAMP} files and run${R}"
echo -e "  ${S}    bash ${STOA_DIR}/setup/enable-limine-snapshots.sh --disable${R}"
echo ""
