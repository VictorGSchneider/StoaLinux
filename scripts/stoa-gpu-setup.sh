#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — GPU + CPU Setup                               ║
# ║  "Adapta-te às coisas com as quais o destino te uniu."      ║
# ║                              — Marco Aurélio                 ║
# ╚══════════════════════════════════════════════════════════════╝
#
# USO:
#   chmod +x scripts/stoa-gpu-setup.sh
#   ./scripts/stoa-gpu-setup.sh
#
# O que este script faz:
#   1. Detecta CPU (AMD/Intel) e instala microcode correto
#   2. Detecta GPU (NVIDIA/AMD/Intel) e instala drivers adequados
#   3. Para NVIDIA: configura mkinitcpio, modprobe e env vars
#   4. Para AMD/Intel GPU: confirma pacotes mesa/vulkan

set -e

# ── Cores ──
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

# ── Verificar Arch ──
if [ ! -f /etc/arch-release ]; then
    echo -e "  ${T}[!] Este script é para Arch Linux.${R}"
    exit 1
fi

if [ "$(id -u)" -eq 0 ]; then
    echo -e "  ${T}[!] Não execute como root. O script usa sudo quando necessário.${R}"
    exit 1
fi

# ══════════════════════════════════════════════════════════════
# Funções de detecção
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

get_gpu_name() {
    lspci 2>/dev/null | grep -iE 'vga|3d|display' | head -1 | sed 's/.*: //' || echo "Desconhecida"
}

detect_nvidia_generation() {
    local device_id id_dec
    device_id=$(lspci -nn 2>/dev/null | grep -i 'nvidia' | grep -oP '\[10de:([0-9a-fA-F]{4})\]' | head -1 | grep -oP '[0-9a-fA-F]{4}' || true)

    if [ -z "$device_id" ]; then
        echo "unknown"
        return
    fi

    id_dec=$((16#${device_id}))

    # Mapeamento aproximado por PCI device ID ranges
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
        echo -e "  ${S}Instalando ${pkg} manualmente via makepkg...${R}"
        local _tmpdir
        _tmpdir=$(mktemp -d)
        git clone "https://aur.archlinux.org/${pkg}.git" "$_tmpdir/$pkg"
        (cd "$_tmpdir/$pkg" && makepkg -si --noconfirm)
        rm -rf "$_tmpdir"
    fi
}

# ══════════════════════════════════════════════════════════════
# [1/5] Detecção de hardware
# ══════════════════════════════════════════════════════════════

echo -e "  ${F}[1/5] Detectando hardware...${R}"
echo ""

# ── CPU ──
CPU_VENDOR=$(detect_cpu)
CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "Desconhecido")
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
        echo -e "  ${T}CPU:  Vendor desconhecido${R}"
        echo -e "  ${S}      Escolha o microcode:${R}"
        echo -e "  ${S}        1) amd-ucode   (AMD)${R}"
        echo -e "  ${S}        2) intel-ucode  (Intel)${R}"
        echo -e "  ${S}        3) Pular${R}"
        read -rp "  Escolha [3]: " CPU_CHOICE
        CPU_CHOICE="${CPU_CHOICE:-3}"
        case "$CPU_CHOICE" in
            1) CPU_UCODE_PKG="amd-ucode" ;;
            2) CPU_UCODE_PKG="intel-ucode" ;;
            *) CPU_UCODE_PKG="" ;;
        esac
        ;;
esac

echo ""

# ── GPU ──
GPU_VENDOR=$(detect_gpu)
GPU_NAME=$(get_gpu_name)
GPU_DRIVER_PKGS=""
NVIDIA_DRIVER=""
NVIDIA_GEN=""
IS_NVIDIA=false
IS_KEPLER=false

case "$GPU_VENDOR" in
    nvidia)
        IS_NVIDIA=true
        NVIDIA_GEN=$(detect_nvidia_generation)

        echo -e "  ${B}GPU:${R}  ${F}${GPU_NAME}${R}"
        echo -e "  ${S}      Vendor: NVIDIA — Geração: ${NVIDIA_GEN}${R}"

        case "$NVIDIA_GEN" in
            blackwell|ada|ampere|turing)
                NVIDIA_DRIVER="nvidia"
                echo -e "  ${S}      Driver recomendado: nvidia (proprietário)${R}"
                echo -e "  ${S}      Alternativa: nvidia-open (kernel aberto, Turing+)${R}"
                ;;
            pascal|maxwell)
                NVIDIA_DRIVER="nvidia"
                echo -e "  ${S}      Driver recomendado: nvidia (proprietário)${R}"
                ;;
            kepler)
                IS_KEPLER=true
                NVIDIA_DRIVER="nvidia-470xx-dkms"
                echo -e "  ${T}      Driver: nvidia-470xx-dkms (AUR — Kepler legacy)${R}"
                echo -e "  ${S}      GTX 600/700 series${R}"
                ;;
            legacy)
                echo -e "  ${T}      GPU muito antiga — driver proprietário pode não existir.${R}"
                echo -e "  ${S}      Recomendação: usar driver Nouveau (open-source).${R}"
                IS_NVIDIA=false
                GPU_DRIVER_PKGS=""
                ;;
            *)
                echo -e "  ${T}      Geração não detectada automaticamente.${R}"
                ;;
        esac

        # Confirmação / override
        if $IS_NVIDIA; then
            echo ""
            echo -e "  ${F}Confirmar driver '${NVIDIA_DRIVER}'? (s/n) [s]:${R}"
            read -rp "  " CONFIRM_DRIVER
            CONFIRM_DRIVER="${CONFIRM_DRIVER:-s}"

            if [ "$CONFIRM_DRIVER" != "s" ]; then
                echo ""
                echo -e "  ${F}Escolha o driver NVIDIA:${R}"
                echo -e "  ${S}    1) nvidia           (Maxwell/Pascal/Turing/Ampere/Ada/Blackwell)${R}"
                echo -e "  ${S}    2) nvidia-open      (Turing+ — módulos kernel abertos)${R}"
                echo -e "  ${S}    3) nvidia-470xx-dkms (Kepler — GTX 600/700, AUR)${R}"
                echo -e "  ${S}    4) Cancelar (usar Nouveau)${R}"
                read -rp "  Escolha [1]: " DRIVER_CHOICE
                DRIVER_CHOICE="${DRIVER_CHOICE:-1}"

                case "$DRIVER_CHOICE" in
                    1) NVIDIA_DRIVER="nvidia"; IS_KEPLER=false ;;
                    2) NVIDIA_DRIVER="nvidia-open"; IS_KEPLER=false ;;
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
            fi
        fi
        ;;
    amd)
        echo -e "  ${B}GPU:${R}  ${F}${GPU_NAME}${R}"
        echo -e "  ${S}      Vendor: AMD/Radeon${R}"
        echo -e "  ${S}      Drivers: mesa vulkan-radeon libva-mesa-driver${R}"
        echo -e "  ${O}      (Geralmente já instalados — open-source funciona nativamente)${R}"
        GPU_DRIVER_PKGS="mesa vulkan-radeon libva-mesa-driver"
        ;;
    intel)
        echo -e "  ${B}GPU:${R}  ${F}${GPU_NAME}${R}"
        echo -e "  ${S}      Vendor: Intel${R}"
        echo -e "  ${S}      Drivers: mesa vulkan-intel intel-media-driver${R}"
        echo -e "  ${O}      (Geralmente já instalados — open-source funciona nativamente)${R}"
        GPU_DRIVER_PKGS="mesa vulkan-intel intel-media-driver"
        ;;
    *)
        echo -e "  ${T}GPU:  Não detectada${R}"
        echo -e "  ${S}      Verifique com: lspci | grep -i vga${R}"
        echo -e "  ${S}      Pulando configuração de GPU.${R}"
        ;;
esac

echo ""

# ══════════════════════════════════════════════════════════════
# [2/5] Instalação de pacotes
# ══════════════════════════════════════════════════════════════

echo -e "  ${F}[2/5] Pacotes${R}"
echo ""

ALL_PKGS=""
[ -n "$CPU_UCODE_PKG" ] && ALL_PKGS="$CPU_UCODE_PKG"
[ -n "$GPU_DRIVER_PKGS" ] && ALL_PKGS="$ALL_PKGS $GPU_DRIVER_PKGS"
ALL_PKGS=$(echo "$ALL_PKGS" | xargs) # trim

if [ -z "$ALL_PKGS" ]; then
    echo -e "  ${S}[~] Nenhum pacote para instalar.${R}"
else
    echo -e "  ${S}Pacotes: ${ALL_PKGS}${R}"
    if $IS_KEPLER; then
        echo -e "  ${T}  + ${NVIDIA_DRIVER} (AUR)${R}"
    fi
    echo ""
    read -rp "  Instalar pacotes? (s/n) [s]: " INSTALL
    INSTALL="${INSTALL:-s}"

    if [ "$INSTALL" = "s" ]; then
        sudo pacman -S --needed $ALL_PKGS
        echo -e "  ${O}[✓] Pacotes oficiais instalados.${R}"

        # Kepler driver via AUR
        if $IS_KEPLER; then
            echo ""
            echo -e "  ${F}Instalando ${NVIDIA_DRIVER} (AUR)...${R}"
            install_aur_package "$NVIDIA_DRIVER"
            echo -e "  ${O}[✓] ${NVIDIA_DRIVER} instalado.${R}"
        fi
    else
        echo -e "  ${S}[~] Pacotes pulados.${R}"
    fi
fi

echo ""

# ══════════════════════════════════════════════════════════════
# [3/5] mkinitcpio — módulos NVIDIA early KMS (somente NVIDIA)
# ══════════════════════════════════════════════════════════════

if $IS_NVIDIA; then
    echo -e "  ${F}[3/5] Configurando mkinitcpio (early KMS)${R}"

    MKINITCPIO="/etc/mkinitcpio.conf"
    NVIDIA_MODULES="nvidia nvidia_modeset nvidia_uvm nvidia_drm"

    if grep -q "nvidia" "$MKINITCPIO" 2>/dev/null; then
        echo -e "  ${S}[~] Módulos NVIDIA já presentes no mkinitcpio.${R}"
    else
        echo -e "  ${S}Adicionando módulos: ${NVIDIA_MODULES}${R}"
        sudo sed -i "s/^MODULES=(\(.*\))/MODULES=(\1 ${NVIDIA_MODULES})/" "$MKINITCPIO"
        sudo sed -i 's/MODULES=( /MODULES=(/' "$MKINITCPIO"
        echo -e "  ${O}[✓] Módulos adicionados.${R}"
        echo -e "  ${S}Regenerando initramfs...${R}"
        sudo mkinitcpio -P
        echo -e "  ${O}[✓] Initramfs regenerado.${R}"
    fi
else
    echo -e "  ${S}[3/5] mkinitcpio — GPU não-NVIDIA, sem alterações necessárias.${R}"
fi

echo ""

# ══════════════════════════════════════════════════════════════
# [4/5] modprobe — nvidia_drm modeset (somente NVIDIA)
# ══════════════════════════════════════════════════════════════

if $IS_NVIDIA; then
    echo -e "  ${F}[4/5] Configurando nvidia-drm modeset${R}"

    MODPROBE_CONF="/etc/modprobe.d/nvidia.conf"
    if [ -f "$MODPROBE_CONF" ] && grep -q "modeset=1" "$MODPROBE_CONF" 2>/dev/null; then
        echo -e "  ${S}[~] nvidia-drm modeset já configurado.${R}"
    else
        echo "options nvidia_drm modeset=1 fbdev=1" | sudo tee "$MODPROBE_CONF" > /dev/null
        echo -e "  ${O}[✓] /etc/modprobe.d/nvidia.conf criado.${R}"
    fi
else
    echo -e "  ${S}[4/5] modprobe — GPU não-NVIDIA, sem alterações necessárias.${R}"
fi

echo ""

# ══════════════════════════════════════════════════════════════
# [5/5] Variáveis de ambiente (somente NVIDIA)
# ══════════════════════════════════════════════════════════════

if $IS_NVIDIA; then
    echo -e "  ${F}[5/5] Ativando variáveis NVIDIA no Hyprland e stoa-env${R}"

    STOA_DIR="$(cd "$(dirname "$0")/.." && pwd)"
    HYPR_CONF="${STOA_DIR}/hyprland/hyprland.conf"
    ENV_FILE="${STOA_DIR}/environment/stoa-env.sh"

    # Hyprland — adicionar env vars se ainda não existem
    if grep -q "LIBVA_DRIVER_NAME" "$HYPR_CONF" 2>/dev/null; then
        echo -e "  ${S}[~] Variáveis NVIDIA já presentes no hyprland.conf.${R}"
    else
        cat >> "$HYPR_CONF" << 'NVIDIA_EOF'

# ── NVIDIA (Wayland) ──
env = LIBVA_DRIVER_NAME, nvidia
env = __GLX_VENDOR_LIBRARY_NAME, nvidia
env = GBM_BACKEND, nvidia-drm
env = NVD_BACKEND, direct
env = WLR_NO_HARDWARE_CURSORS, 1
env = __GL_GSYNC_ALLOWED, 1
env = __GL_VRR_ALLOWED, 1
NVIDIA_EOF
        echo -e "  ${O}[✓] Variáveis NVIDIA adicionadas ao hyprland.conf.${R}"
    fi

    # stoa-env.sh — descomentar as variáveis NVIDIA
    if grep -q "^export LIBVA_DRIVER_NAME" "$ENV_FILE" 2>/dev/null; then
        echo -e "  ${S}[~] Variáveis NVIDIA já ativas no stoa-env.sh.${R}"
    elif grep -q "# export LIBVA_DRIVER_NAME" "$ENV_FILE" 2>/dev/null; then
        sed -i 's/^# export LIBVA_DRIVER_NAME/export LIBVA_DRIVER_NAME/' "$ENV_FILE"
        sed -i 's/^# export __GLX_VENDOR_LIBRARY_NAME/export __GLX_VENDOR_LIBRARY_NAME/' "$ENV_FILE"
        sed -i 's/^# export GBM_BACKEND/export GBM_BACKEND/' "$ENV_FILE"
        sed -i 's/^# export NVD_BACKEND/export NVD_BACKEND/' "$ENV_FILE"
        sed -i 's/^# export WLR_NO_HARDWARE_CURSORS/export WLR_NO_HARDWARE_CURSORS/' "$ENV_FILE"
        sed -i 's/^# export __GL_GSYNC_ALLOWED/export __GL_GSYNC_ALLOWED/' "$ENV_FILE"
        sed -i 's/^# export __GL_VRR_ALLOWED/export __GL_VRR_ALLOWED/' "$ENV_FILE"
        echo -e "  ${O}[✓] Variáveis NVIDIA descomentadas no stoa-env.sh.${R}"
    fi
else
    echo -e "  ${S}[5/5] Variáveis de ambiente — GPU não-NVIDIA, sem alterações necessárias.${R}"
fi

echo ""

# ══════════════════════════════════════════════════════════════
# Resumo
# ══════════════════════════════════════════════════════════════

echo -e "  ${B}╔══════════════════════════════════════════════════════╗${R}"
echo -e "  ${B}║     Setup concluído!                                 ║${R}"
echo -e "  ${B}╚══════════════════════════════════════════════════════╝${R}"
echo ""

echo -e "  ${F}Hardware detectado:${R}"
echo -e "  ${S}  CPU: ${CPU_MODEL}${R}"
echo -e "  ${S}  GPU: ${GPU_NAME}${R}"
echo ""

if [ -n "$CPU_UCODE_PKG" ]; then
    echo -e "  ${F}Microcode:${R}"
    echo -e "  ${S}  ${CPU_UCODE_PKG}${R}"
    echo ""
fi

if $IS_NVIDIA; then
    echo -e "  ${F}NVIDIA configurado:${R}"
    echo -e "  ${S}  Driver: ${NVIDIA_DRIVER}${R}"
    echo -e "  ${S}  nvidia-utils, nvidia-settings, libva-nvidia-driver${R}"
    echo -e "  ${S}  /etc/mkinitcpio.conf — módulos early KMS${R}"
    echo -e "  ${S}  /etc/modprobe.d/nvidia.conf — DRM modeset + fbdev${R}"
    echo -e "  ${S}  hyprland.conf — env vars NVIDIA/Wayland${R}"
    echo -e "  ${S}  stoa-env.sh — env vars NVIDIA${R}"
    echo ""
    echo -e "  ${T}Reinicie o sistema para aplicar as mudanças.${R}"
elif [ "$GPU_VENDOR" = "amd" ]; then
    echo -e "  ${F}AMD GPU:${R}"
    echo -e "  ${S}  mesa, vulkan-radeon, libva-mesa-driver${R}"
    echo -e "  ${O}  Nenhuma configuração extra necessária para Wayland.${R}"
elif [ "$GPU_VENDOR" = "intel" ]; then
    echo -e "  ${F}Intel GPU:${R}"
    echo -e "  ${S}  mesa, vulkan-intel, intel-media-driver${R}"
    echo -e "  ${O}  Nenhuma configuração extra necessária para Wayland.${R}"
fi

echo ""
echo -e "  ${O}\"Suporta e abstém-te.\" — Epicteto${R}"
echo ""
