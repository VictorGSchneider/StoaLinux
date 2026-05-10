#!/bin/bash
# Force bash, not zsh
#[ -n "$ZSH_VERSION" ] && exec bash "$0" "$@"
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — GPU + CPU Setup                               ║
# ║  "Adapt yourself to the things among which your lot          ║
# ║   has been cast."                  — Marcus Aurelius          ║
# ╚══════════════════════════════════════════════════════════════╝
#
# USAGE:
#   chmod +x scripts/stoa-gpu-setup.sh
#   ./scripts/stoa-gpu-setup.sh
#
# What this script does:
#   1. Detects CPU (AMD/Intel) and installs correct microcode
#   2. Detects GPU (NVIDIA/AMD/Intel) and installs appropriate drivers
#   3. For NVIDIA: configures mkinitcpio, modprobe, and env vars
#   4. For AMD/Intel GPU: confirms mesa/vulkan packages

set -e

# ── Colors ──
B='\033[38;2;196;154;92m'
S='\033[38;2;110;106;98m'
F='\033[38;2;212;207;196m'
O='\033[38;2;138;154;108m'
T='\033[38;2;179;107;90m'
R='\033[0m'

echo ""
echo -e "  ${B}╔══════════════════════════════════════════════════════╗${R}"
echo -e "  ${B}║     STOA LINUX — GPU + CPU Setup                     ║${R}"
echo -e "  ${B}╚══════════════════════════════════════════════════════╝${R}"
echo ""

# ── Check Arch ──
if [ ! -f /etc/arch-release ]; then
    echo -e "  ${T}[!] This script is for Arch Linux.${R}"
    exit 1
fi

if [ "$(id -u)" -eq 0 ]; then
    echo -e "  ${T}[!] Do not run as root. The script uses sudo when necessary.${R}"
    exit 1
fi

# ══════════════════════════════════════════════════════════════
# Detection functions
# ══════════════════════════════════════════════════════════════

detect_cpu() {
    local vendor
    vendor=$(grep -m1 'vendor_id' /proc/cpuinfo 2>/dev/null | awk '{print $NF}')
    case "$vendor" in
        AuthenticAMD) echo "amd" ;;
        GenuineIntel) echo "intel" ;;
        *) echo "unknown" ;;
    esac
}

detect_gpu() {
    # Returns the *primary* GPU vendor for driver-selection purposes.
    # If NVIDIA is present we treat it as primary (it owns HDMI on
    # most muxless gaming laptops); the iGPU is reported separately
    # by detect_igpu().
    local vga_line
    vga_line=$(lspci 2>/dev/null | grep -iE 'vga|3d|display' || true)

    if echo "$vga_line" | grep -qi 'nvidia'; then
        echo "nvidia"
    elif echo "$vga_line" | grep -qi 'amd\|radeon'; then
        echo "amd"
    elif echo "$vga_line" | grep -qi 'intel'; then
        echo "intel"
    else
        echo "unknown"
    fi
}

# Detects an AMD/Intel iGPU sitting alongside an NVIDIA dGPU.
# Echoes "amd", "intel", or "" if no secondary GPU is present.
detect_igpu() {
    local vga_line
    vga_line=$(lspci 2>/dev/null | grep -iE 'vga|3d|display' || true)
    # Only meaningful when an NVIDIA card is also present.
    if ! echo "$vga_line" | grep -qi 'nvidia'; then
        echo ""
        return
    fi
    if echo "$vga_line" | grep -iE 'amd|radeon|advanced micro' | grep -qiE 'vga|3d|display'; then
        echo "amd"
    elif echo "$vga_line" | grep -i 'intel' | grep -qiE 'vga|3d|display'; then
        echo "intel"
    else
        echo ""
    fi
}

# Lists every installed kernel package (linux, linux-zen, linux-lts, ...).
# nvidia-dkms is required whenever a non-default kernel is installed,
# because the prebuilt `nvidia` package only ships modules for `linux`.
detect_kernels() {
    pacman -Qq 2>/dev/null | grep -E '^linux(-zen|-lts|-hardened|-rt|-rt-lts)?$' || true
}

needs_dkms() {
    # Returns 0 (true) if any kernel other than plain `linux` is installed.
    local kernels
    kernels=$(detect_kernels)
    [ -z "$kernels" ] && return 1
    echo "$kernels" | grep -qvE '^linux$'
}

get_gpu_name() {
    lspci 2>/dev/null | grep -iE 'vga|3d|display' | head -1 | sed 's/.*: //' || echo "Unknown"
}

detect_nvidia_generation() {
    local device_id id_dec
    
    # Filtra ESPECIFICAMENTE pela linha VGA (GPU dedicada)
    # Não pega audio ou outros periféricos NVIDIA
    # Extrai APENAS o device ID (a parte depois de "10de:")
    device_id=$(lspci -nn 2>/dev/null | grep -i 'nvidia' | grep -iE 'vga|3d|display' | grep -oP '\[10de:\K[0-9a-fA-F]{4}' | head -1 || true)

    if [ -z "$device_id" ]; then
        echo "unknown"
        return
    fi

    # Remove espaços (safety)
    device_id=$(echo "$device_id" | xargs)

    # Debug (opcional, remova depois)
    #echo "DEBUG: device_id = $device_id" >&2
    
    id_dec=$((16#${device_id}))

    # Approximate mapping by PCI device ID ranges
    # Blackwell:    ≥0x2900 (GB2xx) — RTX 5000
    # Ada Lovelace: ≥0x2600 (AD1xx) — RTX 4000
    # Ampere:       ≥0x2200 (GA1xx) — RTX 3000
    # Turing:       ≥0x1E00 (TU1xx) — RTX 2000, GTX 1650/1660
    # Pascal:       ≥0x1B00 (GP1xx) — GTX 1000
    # Maxwell:      ≥0x1340 (GM1xx) — GTX 900
    # Kepler:       ≥0x0FC0 (GK1xx) — GTX 600/700

    if [ "$id_dec" -ge $((16#2900)) ]; then
        echo "blackwell"
    elif [ "$id_dec" -ge $((16#2600)) ]; then
        echo "ada"
    elif [ "$id_dec" -ge $((16#2200)) ]; then
        echo "ampere"
    elif [ "$id_dec" -ge $((16#1E00)) ]; then
        echo "turing"
    elif [ "$id_dec" -ge $((16#1B00)) ]; then
        echo "pascal"
    elif [ "$id_dec" -ge $((16#1340)) ]; then
        echo "maxwell"
    elif [ "$id_dec" -ge $((16#0FC0)) ]; then
        echo "kepler"
    else
        echo "legacy"
    fi
}

install_aur_package() {
    local pkg="$1"
    if command -v yay &>/dev/null; then
        yay -S --needed --noconfirm "$pkg"
    elif command -v paru &>/dev/null; then
        paru -S --needed --noconfirm "$pkg"
    else
        echo -e "  ${S}Installing ${pkg} manually via makepkg...${R}"
        local _tmpdir
        _tmpdir=$(mktemp -d)
        git clone "https://aur.archlinux.org/${pkg}.git" "$_tmpdir/$pkg"
        (cd "$_tmpdir/$pkg" && makepkg -si --noconfirm)
        rm -rf "$_tmpdir"
    fi
}

# ══════════════════════════════════════════════════════════════
# [1/5] Hardware detection
# ══════════════════════════════════════════════════════════════

echo -e "  ${F}[1/5] Detecting hardware...${R}"
echo ""

# ── CPU ──
CPU_VENDOR=$(detect_cpu)
CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "Unknown")
CPU_UCODE_PKG=""

case "$CPU_VENDOR" in
    amd)
        CPU_UCODE_PKG="amd-ucode"
        echo -e "  ${B}CPU:${R}  ${F}${CPU_MODEL}${R}"
        echo -e "  ${S}      Vendor: AMD → microcode: ${CPU_UCODE_PKG}${R}"
        ;;
    intel)
        CPU_UCODE_PKG="intel-ucode"
        echo -e "  ${B}CPU:${R}  ${F}${CPU_MODEL}${R}"
        echo -e "  ${S}      Vendor: Intel → microcode: ${CPU_UCODE_PKG}${R}"
        ;;
    *)
        echo -e "  ${T}CPU:  Unknown vendor${R}"
        echo -e "  ${S}      Choose the microcode:${R}"
        echo -e "  ${S}        1) amd-ucode   (AMD)${R}"
        echo -e "  ${S}        2) intel-ucode  (Intel)${R}"
        echo -e "  ${S}        3) Skip${R}"
        read -rp "  Choose [3]: " CPU_CHOICE
        CPU_CHOICE="${CPU_CHOICE:-3}"
        case "$CPU_CHOICE" in
            1) CPU_UCODE_PKG="amd-ucode" ;;
            2) CPU_UCODE_PKG="intel-ucode" ;;
            *) CPU_UCODE_PKG="" ;;
        esac
        ;;
esac

echo ""

# ── Kernel(s) ──
INSTALLED_KERNELS=$(detect_kernels)
USE_DKMS=false
if needs_dkms; then
    USE_DKMS=true
fi
if [ -n "$INSTALLED_KERNELS" ]; then
    echo -e "  ${B}Kernel:${R} ${F}$(echo "$INSTALLED_KERNELS" | tr '\n' ' ')${R}"
    if $USE_DKMS; then
        echo -e "  ${S}      Non-default kernel detected → will use DKMS NVIDIA driver.${R}"
    fi
    echo ""
fi

# ── GPU ──
GPU_VENDOR=$(detect_gpu)
GPU_NAME=$(get_gpu_name)
IGPU_VENDOR=$(detect_igpu)
GPU_DRIVER_PKGS=""
IGPU_DRIVER_PKGS=""
NVIDIA_DRIVER=""
NVIDIA_GEN=""
IS_NVIDIA=false
IS_KEPLER=false
IS_HYBRID=false
[ -n "$IGPU_VENDOR" ] && IS_HYBRID=true

case "$GPU_VENDOR" in
    nvidia)
        IS_NVIDIA=true
        NVIDIA_GEN=$(detect_nvidia_generation)

        echo -e "  ${B}GPU:${R}  ${F}${GPU_NAME}${R}"
        echo -e "  ${S}      Vendor: NVIDIA — Generation: ${NVIDIA_GEN}${R}"

        # Pick the right metapackage. `nvidia` only ships modules for
        # the stock `linux` kernel; anything else (linux-zen / -lts /
        # -hardened) MUST use the DKMS variant or the module won't
        # build on kernel updates.
        if $USE_DKMS; then
            _nv_default="nvidia-dkms"
            _nv_open="nvidia-open-dkms"
        else
            _nv_default="nvidia"
            _nv_open="nvidia-open"
        fi

        case "$NVIDIA_GEN" in
            blackwell|ada|ampere|turing)
                NVIDIA_DRIVER="$_nv_default"
                echo -e "  ${S}      Recommended driver: ${_nv_default} (proprietary)${R}"
                echo -e "  ${S}      Alternative: ${_nv_open} (open kernel modules, Turing+)${R}"
                ;;
            pascal|maxwell)
                NVIDIA_DRIVER="$_nv_default"
                echo -e "  ${S}      Recommended driver: ${_nv_default} (proprietary)${R}"
                ;;
            kepler)
                IS_KEPLER=true
                NVIDIA_DRIVER="nvidia-470xx-dkms"
                echo -e "  ${T}      Driver: nvidia-470xx-dkms (AUR — Kepler legacy)${R}"
                echo -e "  ${S}      GTX 600/700 series${R}"
                ;;
            legacy)
                echo -e "  ${T}      GPU too old — proprietary driver may not exist.${R}"
                echo -e "  ${S}      Recommendation: use Nouveau driver (open-source).${R}"
                IS_NVIDIA=false
                GPU_DRIVER_PKGS=""
                ;;
            *)
                echo -e "  ${T}      Generation not detected automatically.${R}"
                ;;
        esac

        # Confirmation / override
        if $IS_NVIDIA; then
            echo ""
            echo -e "  ${F}Confirm driver '${NVIDIA_DRIVER}'? (y/n) [y]:${R}"
            read -rp "  " CONFIRM_DRIVER
            CONFIRM_DRIVER="${CONFIRM_DRIVER:-y}"

            if [ "$CONFIRM_DRIVER" != "y" ]; then
                echo ""
                echo -e "  ${F}Choose NVIDIA driver:${R}"
                echo -e "  ${S}    1) ${_nv_default}        (Maxwell/Pascal/Turing/Ampere/Ada/Blackwell)${R}"
                echo -e "  ${S}    2) ${_nv_open}     (Turing+ — open kernel modules)${R}"
                echo -e "  ${S}    3) nvidia-470xx-dkms (Kepler — GTX 600/700, AUR)${R}"
                echo -e "  ${S}    4) Cancel (use Nouveau)${R}"
                read -rp "  Choose [1]: " DRIVER_CHOICE
                DRIVER_CHOICE="${DRIVER_CHOICE:-1}"

                case "$DRIVER_CHOICE" in
                    1) NVIDIA_DRIVER="$_nv_default"; IS_KEPLER=false ;;
                    2) NVIDIA_DRIVER="$_nv_open"; IS_KEPLER=false ;;
                    3) NVIDIA_DRIVER="nvidia-470xx-dkms"; IS_KEPLER=true ;;
                    4) IS_NVIDIA=false; NVIDIA_DRIVER="" ;;
                esac
            fi

            if $IS_NVIDIA; then
                if $IS_KEPLER; then
                    # Kepler: driver via AUR, utils via pacman
                    GPU_DRIVER_PKGS="nvidia-utils nvidia-settings libva-nvidia-driver"
                else
                    GPU_DRIVER_PKGS="${NVIDIA_DRIVER} nvidia-utils nvidia-settings libva-nvidia-driver"
                fi

                # Hybrid laptop: also install the iGPU's mesa stack so
                # the desktop renders on the iGPU and the dGPU only
                # wakes up for HDMI / offload (PRIME render offload).
                if $IS_HYBRID; then
                    case "$IGPU_VENDOR" in
                        amd)
                            # mesa-vdpau used to ship the radeonsi VDPAU
                            # driver as a separate package; on modern
                            # Arch it has been folded back into `mesa`
                            # and is no longer a valid pacman target.
                            IGPU_DRIVER_PKGS="mesa vulkan-radeon libva-mesa-driver"
                            echo -e "  ${O}      Hybrid: AMD iGPU + NVIDIA dGPU detected.${R}"
                            echo -e "  ${S}      Adding: ${IGPU_DRIVER_PKGS}${R}"
                            ;;
                        intel)
                            IGPU_DRIVER_PKGS="mesa vulkan-intel intel-media-driver"
                            echo -e "  ${O}      Hybrid: Intel iGPU + NVIDIA dGPU detected.${R}"
                            echo -e "  ${S}      Adding: ${IGPU_DRIVER_PKGS}${R}"
                            ;;
                    esac
                fi
            fi
        fi
        ;;
    amd)
        echo -e "  ${B}GPU:${R}  ${F}${GPU_NAME}${R}"
        echo -e "  ${S}      Vendor: AMD/Radeon${R}"
        echo -e "  ${S}      Drivers: mesa vulkan-radeon libva-mesa-driver${R}"
        echo -e "  ${O}      (Usually already installed — open-source works natively)${R}"
        GPU_DRIVER_PKGS="mesa vulkan-radeon libva-mesa-driver"
        ;;
    intel)
        echo -e "  ${B}GPU:${R}  ${F}${GPU_NAME}${R}"
        echo -e "  ${S}      Vendor: Intel${R}"
        echo -e "  ${S}      Drivers: mesa vulkan-intel intel-media-driver${R}"
        echo -e "  ${O}      (Usually already installed — open-source works natively)${R}"
        GPU_DRIVER_PKGS="mesa vulkan-intel intel-media-driver"
        ;;
    *)
        echo -e "  ${T}GPU:  Not detected${R}"
        echo -e "  ${S}      Check with: lspci | grep -i vga${R}"
        echo -e "  ${S}      Skipping GPU configuration.${R}"
        ;;
esac

echo ""

# ══════════════════════════════════════════════════════════════
# [2/5] Package installation
# ══════════════════════════════════════════════════════════════

echo -e "  ${F}[2/5] Packages${R}"
echo ""

ALL_PKGS=""
[ -n "$CPU_UCODE_PKG" ] && ALL_PKGS="$CPU_UCODE_PKG"
[ -n "$GPU_DRIVER_PKGS" ] && ALL_PKGS="$ALL_PKGS $GPU_DRIVER_PKGS"
[ -n "$IGPU_DRIVER_PKGS" ] && ALL_PKGS="$ALL_PKGS $IGPU_DRIVER_PKGS"

# DKMS needs kernel headers for every kernel it has to build against,
# otherwise `mkinitcpio -P` reports `module not found: nvidia` for any
# kernel that's installed but missing -headers. Add headers for each
# detected kernel package.
HEADER_PKGS=""
if $IS_NVIDIA && $USE_DKMS; then
    for k in $INSTALLED_KERNELS; do
        HEADER_PKGS="$HEADER_PKGS ${k}-headers"
    done
    [ -n "$HEADER_PKGS" ] && ALL_PKGS="$ALL_PKGS $HEADER_PKGS"
fi

ALL_PKGS=$(echo "$ALL_PKGS" | xargs) # trim

if [ -z "$ALL_PKGS" ]; then
    echo -e "  ${S}[~] No packages to install.${R}"
else
    echo -e "  ${S}Packages: ${ALL_PKGS}${R}"
    if $IS_KEPLER; then
        echo -e "  ${T}  + ${NVIDIA_DRIVER} (AUR)${R}"
    fi
    echo ""
    read -rp "  Install packages? (y/n) [y]: " INSTALL
    INSTALL="${INSTALL:-y}"

    if [ "$INSTALL" = "y" ]; then
        sudo pacman -S --needed $ALL_PKGS
        echo -e "  ${O}[✓] Official packages installed.${R}"

        # Kepler driver via AUR
        if $IS_KEPLER; then
            echo ""
            echo -e "  ${F}Installing ${NVIDIA_DRIVER} (AUR)...${R}"
            install_aur_package "$NVIDIA_DRIVER"
            echo -e "  ${O}[✓] ${NVIDIA_DRIVER} installed.${R}"
        fi

        # Force DKMS to build the NVIDIA module against every installed
        # kernel. Without this, the next mkinitcpio -P fails with
        # `module not found: nvidia` for any kernel whose headers were
        # only just installed.
        if $IS_NVIDIA && $USE_DKMS && command -v dkms >/dev/null 2>&1; then
            echo -e "  ${S}Running dkms autoinstall for all kernels...${R}"
            sudo dkms autoinstall || true
            echo -e "  ${O}[✓] DKMS modules built.${R}"
        fi
    else
        echo -e "  ${S}[~] Packages skipped.${R}"
    fi
fi

echo ""

# ══════════════════════════════════════════════════════════════
# [3/5] mkinitcpio — NVIDIA early KMS modules (NVIDIA only)
# ══════════════════════════════════════════════════════════════

if $IS_NVIDIA; then
    echo -e "  ${F}[3/5] Configuring mkinitcpio (early KMS)${R}"

    MKINITCPIO="/etc/mkinitcpio.conf"
    NVIDIA_MODULES="nvidia nvidia_modeset nvidia_uvm nvidia_drm"

    # Only treat the MODULES=(...) line as authoritative — comments or
    # other lines mentioning "nvidia" must not skip the edit.
    if grep -qE '^\s*MODULES=\([^)]*nvidia' "$MKINITCPIO" 2>/dev/null; then
        echo -e "  ${S}[~] NVIDIA modules already present in mkinitcpio.${R}"
    else
        echo -e "  ${S}Adding modules: ${NVIDIA_MODULES}${R}"
        sudo sed -i "s/^MODULES=(\(.*\))/MODULES=(\1 ${NVIDIA_MODULES})/" "$MKINITCPIO"
        sudo sed -i 's/MODULES=( /MODULES=(/' "$MKINITCPIO"
        echo -e "  ${O}[✓] Modules added.${R}"
        echo -e "  ${S}Regenerating initramfs...${R}"
        sudo mkinitcpio -P
        echo -e "  ${O}[✓] Initramfs regenerated.${R}"
    fi
else
    echo -e "  ${S}[3/5] mkinitcpio — non-NVIDIA GPU, no changes needed.${R}"
fi

echo ""

# ══════════════════════════════════════════════════════════════
# [4/5] modprobe — nvidia_drm modeset (NVIDIA only)
# ══════════════════════════════════════════════════════════════

if $IS_NVIDIA; then
    echo -e "  ${F}[4/5] Configuring nvidia-drm modeset + nouveau blacklist${R}"

    NV_MODPROBE_CHANGED=false

    # Bumblebee was the pre-2019 way to drive NVIDIA Optimus; it ships
    # /usr/lib/modprobe.d/bumblebee.conf with `blacklist nvidia`,
    # `blacklist nvidia-drm`, `blacklist nvidia-modeset`, and
    # `blacklist nvidia-uvm`. Coexisting with the modern PRIME stack
    # means nvidia_modeset / nvidia_drm refuse to autoload at boot,
    # the dGPU stays in D3cold, and HDMI on the dGPU port goes dark.
    # Drop bumblebee whenever we're configuring the proprietary driver.
    if pacman -Qq bumblebee >/dev/null 2>&1; then
        echo -e "  ${T}      Bumblebee detected (deprecated, conflicts with PRIME).${R}"
        echo -e "  ${S}      Removing bumblebee + bbswitch...${R}"
        sudo pacman -Rns --noconfirm bumblebee bbswitch 2>/dev/null || \
            sudo pacman -Rns --noconfirm bumblebee 2>/dev/null || true
        NV_MODPROBE_CHANGED=true
    fi
    if [ -f /usr/lib/modprobe.d/bumblebee.conf ]; then
        echo -e "  ${S}      Removing leftover /usr/lib/modprobe.d/bumblebee.conf...${R}"
        sudo rm -f /usr/lib/modprobe.d/bumblebee.conf
        NV_MODPROBE_CHANGED=true
    fi

    MODPROBE_CONF="/etc/modprobe.d/nvidia.conf"
    # Build the desired contents, then only write if different so
    # re-runs don't bump mkinitcpio unnecessarily.
    NV_MODPROBE_DESIRED=$(cat <<'EOF'
options nvidia_drm modeset=1
# Keep the dGPU in PCI D0 (always-on) so HDMI hot-plug on the dGPU
# port works without a "wake the card up" round trip. Costs ~3-5W
# at idle but matches expectations for presentation laptops.
options nvidia NVreg_DynamicPowerManagement=0x00
# Save vidmem across suspend so resuming on battery doesn't blank
# the screen.
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOF
    )
    if ! [ -f "$MODPROBE_CONF" ] || \
       ! diff -q <(printf '%s\n' "$NV_MODPROBE_DESIRED") "$MODPROBE_CONF" >/dev/null 2>&1; then
        printf '%s\n' "$NV_MODPROBE_DESIRED" | sudo tee "$MODPROBE_CONF" > /dev/null
        echo -e "  ${O}[✓] /etc/modprobe.d/nvidia.conf written (modeset + always-on PM).${R}"
        NV_MODPROBE_CHANGED=true
    else
        echo -e "  ${S}[~] /etc/modprobe.d/nvidia.conf already up to date.${R}"
    fi

    # Nouveau must be out of the way before nvidia loads, otherwise
    # the proprietary driver fails to bind on some boots and HDMI
    # comes up using Nouveau (which can't drive RTX 4000-series).
    NOUVEAU_BLACKLIST="/etc/modprobe.d/blacklist-nouveau.conf"
    if [ -f "$NOUVEAU_BLACKLIST" ] && grep -q '^blacklist nouveau' "$NOUVEAU_BLACKLIST" 2>/dev/null; then
        echo -e "  ${S}[~] Nouveau already blacklisted.${R}"
    else
        printf 'blacklist nouveau\noptions nouveau modeset=0\n' | sudo tee "$NOUVEAU_BLACKLIST" > /dev/null
        echo -e "  ${O}[✓] Nouveau blacklisted.${R}"
        NV_MODPROBE_CHANGED=true
    fi

    # nvidia-utils ships /usr/lib/systemd/system/nvidia-{suspend,resume,
    # hibernate}.service. They aren't enabled by default but are
    # required for the dGPU to round-trip cleanly through suspend.
    for svc in nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service; do
        if systemctl list-unit-files "$svc" >/dev/null 2>&1; then
            if ! systemctl is-enabled --quiet "$svc" 2>/dev/null; then
                sudo systemctl enable "$svc" >/dev/null 2>&1 || true
                echo -e "  ${O}[✓] Enabled ${svc}.${R}"
            fi
        fi
    done

    # If we touched any modprobe.d entry the running initramfs is
    # stale; rebuild it so the changes apply on next boot.
    if $NV_MODPROBE_CHANGED; then
        echo -e "  ${S}modprobe.d changed → regenerating initramfs...${R}"
        sudo mkinitcpio -P
        echo -e "  ${O}[✓] Initramfs regenerated.${R}"
    fi
else
    echo -e "  ${S}[4/5] modprobe — non-NVIDIA GPU, no changes needed.${R}"
fi

echo ""

# ══════════════════════════════════════════════════════════════
# [5/5] Environment variables (NVIDIA only)
# ══════════════════════════════════════════════════════════════

echo -e "  ${F}[5/5] Configuring environment variables (Hyprland + stoa-env)${R}"

STOA_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HYPR_CONF="${STOA_DIR}/config/hypr/hyprland.conf"
ENV_FILE="${STOA_DIR}/shell/stoa-env.sh"

# Helper: uncomment a `# export FOO=...` line in stoa-env.sh.
_uncomment_env() {
    local key="$1"
    sed -i "s|^# export ${key}=|export ${key}=|" "$ENV_FILE"
}

if $IS_NVIDIA; then
    # On a hybrid laptop the iGPU still drives the desktop; VAAPI
    # should target the iGPU vendor. Only set LIBVA_DRIVER_NAME=nvidia
    # on dGPU-only systems.
    if $IS_HYBRID; then
        case "$IGPU_VENDOR" in
            amd)
                _uncomment_env LIBVA_DRIVER_NAME
                sed -i 's|^export LIBVA_DRIVER_NAME=.*|export LIBVA_DRIVER_NAME=radeonsi|' "$ENV_FILE"
                _uncomment_env VDPAU_DRIVER
                sed -i 's|^export VDPAU_DRIVER=.*|export VDPAU_DRIVER=radeonsi|' "$ENV_FILE"
                ;;
            intel)
                _uncomment_env LIBVA_DRIVER_NAME
                sed -i 's|^export LIBVA_DRIVER_NAME=.*|export LIBVA_DRIVER_NAME=iHD|' "$ENV_FILE"
                _uncomment_env VDPAU_DRIVER
                sed -i 's|^export VDPAU_DRIVER=.*|export VDPAU_DRIVER=va_gl|' "$ENV_FILE"
                ;;
        esac
        # Variables that are still safe / desirable on hybrid:
        _uncomment_env WLR_NO_HARDWARE_CURSORS
        _uncomment_env __GL_GSYNC_ALLOWED
        _uncomment_env __GL_VRR_ALLOWED
        echo -e "  ${O}[✓] Hybrid env vars set (iGPU=${IGPU_VENDOR} VAAPI, NVIDIA for offload/HDMI).${R}"
    else
        # Pure NVIDIA system.
        for v in LIBVA_DRIVER_NAME VDPAU_DRIVER __GLX_VENDOR_LIBRARY_NAME GBM_BACKEND \
                 NVD_BACKEND WLR_NO_HARDWARE_CURSORS __GL_GSYNC_ALLOWED __GL_VRR_ALLOWED; do
            _uncomment_env "$v"
        done
        echo -e "  ${O}[✓] NVIDIA env vars uncommented in stoa-env.sh.${R}"
    fi

    # Hyprland: drop a stoa-managed env block (idempotent — wrapped
    # in a marker so we can rewrite it without dragging stale vars).
    HYPR_MARKER_BEGIN="# >>> stoa-gpu-setup: env (auto-managed) >>>"
    HYPR_MARKER_END="# <<< stoa-gpu-setup: env (auto-managed) <<<"
    if grep -qF "$HYPR_MARKER_BEGIN" "$HYPR_CONF" 2>/dev/null; then
        # Strip the previous block before writing the new one.
        sed -i "/$HYPR_MARKER_BEGIN/,/$HYPR_MARKER_END/d" "$HYPR_CONF"
    fi

    # Resolve the NVIDIA card path NOW so we can write a literal value
    # (Hyprland does not expand $(...) in env lines).
    #
    # IMPORTANT: AQ_DRM_DEVICES / WLR_DRM_DEVICES are colon-separated
    # lists of paths. The /dev/dri/by-path/pci-0000:XX:XX.X-card form
    # contains colons inside the path itself, which Aquamarine
    # mis-parses as multiple device entries:
    #
    #   ERR drm: Failed to canonicalize path /dev/dri/by-path/pci-0000
    #   ERR drm: Failed to canonicalize path 01
    #   ERR drm: Failed to canonicalize path 00.0-card
    #   ERR drm: Found no gpus to use, cannot continue
    #
    # Workaround: install a udev rule that creates a stable symlink
    # /dev/dri/nvidia-card pointing at whichever cardN is the NVIDIA
    # device, and use that path (no colons).
    NV_CARD_PATH=""
    if $IS_HYBRID; then
        NV_UDEV_RULE="/etc/udev/rules.d/99-stoa-nvidia-drm.rules"
        if [ ! -f "$NV_UDEV_RULE" ] || ! grep -q 'nvidia-card' "$NV_UDEV_RULE" 2>/dev/null; then
            echo -e "  ${S}Installing udev rule for stable NVIDIA DRM symlink...${R}"
            printf '%s\n' \
                '# stoa-gpu-setup: stable symlink to the NVIDIA DRM card so' \
                '# AQ_DRM_DEVICES / WLR_DRM_DEVICES can avoid the by-path' \
                '# form (which contains colons and breaks the parser).' \
                'SUBSYSTEM=="drm", KERNEL=="card[0-9]*", ATTRS{vendor}=="0x10de", SYMLINK+="dri/nvidia-card"' \
                | sudo tee "$NV_UDEV_RULE" > /dev/null
            sudo udevadm control --reload-rules
            sudo udevadm trigger --subsystem-match=drm
        fi
        # Wait briefly for the symlink to settle.
        for _ in 1 2 3 4 5; do
            [ -e /dev/dri/nvidia-card ] && break
            sleep 0.2
        done
        if [ -e /dev/dri/nvidia-card ]; then
            NV_CARD_PATH="/dev/dri/nvidia-card"
        else
            # Fallback: scan /sys for the cardN whose vendor is 0x10de.
            for c in /sys/class/drm/card[0-9]*; do
                v=$(cat "$c/device/vendor" 2>/dev/null || true)
                if [ "$v" = "0x10de" ]; then
                    NV_CARD_PATH="/dev/dri/$(basename "$c")"
                    break
                fi
            done
        fi
    fi

    {
        echo ""
        echo "$HYPR_MARKER_BEGIN"
        if $IS_HYBRID; then
            echo "# Hybrid laptop (${IGPU_VENDOR} iGPU + NVIDIA dGPU, muxless HDMI):"
            echo "# Force NVIDIA as primary KMS device so HDMI on the dGPU port works."
            if [ -n "$NV_CARD_PATH" ]; then
                echo "env = AQ_DRM_DEVICES, ${NV_CARD_PATH}"
                echo "env = WLR_DRM_DEVICES, ${NV_CARD_PATH}"
            else
                echo "# (NVIDIA card could not be resolved automatically — set"
                echo "#  AQ_DRM_DEVICES manually to /dev/dri/cardN, where cardN"
                echo "#  is the one whose /sys/class/drm/cardN/device/vendor is 0x10de."
                echo "#  Do NOT use /dev/dri/by-path/... — it contains ':' which"
                echo "#  Aquamarine mis-parses as a list separator.)"
            fi
            echo "env = __NV_PRIME_RENDER_OFFLOAD, 1"
            echo "env = __VK_LAYER_NV_optimus, NVIDIA_only"
            case "$IGPU_VENDOR" in
                amd)   echo "env = LIBVA_DRIVER_NAME, radeonsi" ;;
                intel) echo "env = LIBVA_DRIVER_NAME, iHD" ;;
            esac
        else
            echo "# Pure NVIDIA (Wayland):"
            echo "env = LIBVA_DRIVER_NAME, nvidia"
            echo "env = __GLX_VENDOR_LIBRARY_NAME, nvidia"
            echo "env = GBM_BACKEND, nvidia-drm"
            echo "env = NVD_BACKEND, direct"
        fi
        echo "env = WLR_NO_HARDWARE_CURSORS, 1"
        echo "env = __GL_GSYNC_ALLOWED, 1"
        echo "env = __GL_VRR_ALLOWED, 1"
        echo "$HYPR_MARKER_END"
    } >> "$HYPR_CONF"
    echo -e "  ${O}[✓] hyprland.conf env block updated.${R}"
    [ -n "$NV_CARD_PATH" ] && echo -e "  ${S}      NVIDIA DRM card: ${NV_CARD_PATH}${R}"

elif [ "$GPU_VENDOR" = "amd" ]; then
    _uncomment_env LIBVA_DRIVER_NAME
    sed -i 's|^export LIBVA_DRIVER_NAME=.*|export LIBVA_DRIVER_NAME=radeonsi|' "$ENV_FILE"
    _uncomment_env VDPAU_DRIVER
    sed -i 's|^export VDPAU_DRIVER=.*|export VDPAU_DRIVER=radeonsi|' "$ENV_FILE"
    echo -e "  ${O}[✓] AMD VAAPI/VDPAU env vars set.${R}"

elif [ "$GPU_VENDOR" = "intel" ]; then
    _uncomment_env LIBVA_DRIVER_NAME
    sed -i 's|^export LIBVA_DRIVER_NAME=.*|export LIBVA_DRIVER_NAME=iHD|' "$ENV_FILE"
    _uncomment_env VDPAU_DRIVER
    sed -i 's|^export VDPAU_DRIVER=.*|export VDPAU_DRIVER=va_gl|' "$ENV_FILE"
    echo -e "  ${O}[✓] Intel VAAPI/VDPAU env vars set.${R}"

else
    echo -e "  ${S}[~] Unknown GPU — leaving env vars untouched.${R}"
fi

echo ""

# ══════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════

echo -e "  ${B}╔══════════════════════════════════════════════════════╗${R}"
echo -e "  ${B}║     Setup complete!                                  ║${R}"
echo -e "  ${B}╚══════════════════════════════════════════════════════╝${R}"
echo ""

echo -e "  ${F}Detected hardware:${R}"
echo -e "  ${S}  CPU: ${CPU_MODEL}${R}"
echo -e "  ${S}  GPU: ${GPU_NAME}${R}"
echo ""

if [ -n "$CPU_UCODE_PKG" ]; then
    echo -e "  ${F}Microcode:${R}"
    echo -e "  ${S}  ${CPU_UCODE_PKG}${R}"
    echo ""
fi

if $IS_NVIDIA; then
    echo -e "  ${F}NVIDIA configured:${R}"
    echo -e "  ${S}  Driver: ${NVIDIA_DRIVER}${R}"
    if $IS_HYBRID; then
        echo -e "  ${S}  Hybrid: ${IGPU_VENDOR} iGPU + NVIDIA dGPU${R}"
        echo -e "  ${S}  iGPU: ${IGPU_DRIVER_PKGS}${R}"
        echo -e "  ${S}  HDMI on dGPU via AQ_DRM_DEVICES${R}"
    fi
    echo -e "  ${S}  nvidia-utils, nvidia-settings, libva-nvidia-driver${R}"
    echo -e "  ${S}  /etc/mkinitcpio.conf — early KMS modules${R}"
    echo -e "  ${S}  /etc/modprobe.d/nvidia.conf — DRM modeset + always-on PM${R}"
    echo -e "  ${S}  /etc/modprobe.d/blacklist-nouveau.conf${R}"
    echo -e "  ${S}  bumblebee (deprecated) removed if present${R}"
    echo -e "  ${S}  nvidia-{suspend,resume,hibernate}.service enabled${R}"
    echo -e "  ${S}  hyprland.conf — Wayland env vars${R}"
    echo -e "  ${S}  stoa-env.sh — VAAPI/VDPAU env vars${R}"
    echo ""
    echo -e "  ${T}Reboot the system to apply changes.${R}"
elif [ "$GPU_VENDOR" = "amd" ]; then
    echo -e "  ${F}AMD GPU:${R}"
    echo -e "  ${S}  mesa, vulkan-radeon, libva-mesa-driver${R}"
    echo -e "  ${O}  No extra configuration needed for Wayland.${R}"
elif [ "$GPU_VENDOR" = "intel" ]; then
    echo -e "  ${F}Intel GPU:${R}"
    echo -e "  ${S}  mesa, vulkan-intel, intel-media-driver${R}"
    echo -e "  ${O}  No extra configuration needed for Wayland.${R}"
fi

echo ""
echo -e "  ${O}\"Endure and renounce.\" — Epictetus${R}"
echo ""
