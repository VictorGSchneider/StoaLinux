#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — NVIDIA Setup (AMD CPU + NVIDIA GPU)           ║
# ║  "Adapta-te às coisas com as quais o destino te uniu."      ║
# ║                              — Marco Aurélio                 ║
# ╚══════════════════════════════════════════════════════════════╝
#
# USO:
#   chmod +x scripts/stoa-nvidia-setup.sh
#   ./scripts/stoa-nvidia-setup.sh
#
# O que este script faz:
#   1. Instala driver NVIDIA proprietário + utils
#   2. Instala microcode AMD
#   3. Ativa variáveis de ambiente NVIDIA para Wayland
#   4. Configura mkinitcpio (módulos early KMS)
#   5. Adiciona env vars ao Hyprland

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
echo -e "  ${B}║     STOA LINUX — NVIDIA + AMD Setup                  ║${R}"
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
# 1. Pacotes
# ══════════════════════════════════════════════════════════════

echo -e "  ${F}[1/4] Pacotes NVIDIA + AMD microcode${R}"
echo ""

NVIDIA_PKGS="nvidia nvidia-utils nvidia-settings libva-nvidia-driver"
AMD_PKGS="amd-ucode"

echo -e "  ${S}NVIDIA:   ${NVIDIA_PKGS}${R}"
echo -e "  ${S}AMD CPU:  ${AMD_PKGS}${R}"
echo ""

read -rp "  Instalar pacotes? (s/n) [s]: " INSTALL
INSTALL="${INSTALL:-s}"

if [ "$INSTALL" = "s" ]; then
    sudo pacman -S --needed $NVIDIA_PKGS $AMD_PKGS
    echo -e "  ${O}[✓] Pacotes instalados.${R}"
else
    echo -e "  ${S}[~] Pacotes pulados.${R}"
fi

echo ""

# ══════════════════════════════════════════════════════════════
# 2. mkinitcpio — módulos NVIDIA early KMS
# ══════════════════════════════════════════════════════════════

echo -e "  ${F}[2/4] Configurando mkinitcpio (early KMS)${R}"

MKINITCPIO="/etc/mkinitcpio.conf"
NVIDIA_MODULES="nvidia nvidia_modeset nvidia_uvm nvidia_drm"

if grep -q "nvidia" "$MKINITCPIO" 2>/dev/null; then
    echo -e "  ${S}[~] Módulos NVIDIA já presentes no mkinitcpio.${R}"
else
    echo -e "  ${S}Adicionando módulos: ${NVIDIA_MODULES}${R}"
    sudo sed -i "s/^MODULES=(\(.*\))/MODULES=(\1 ${NVIDIA_MODULES})/" "$MKINITCPIO"
    # Limpar espaço extra se MODULES estava vazio
    sudo sed -i 's/MODULES=( /MODULES=(/' "$MKINITCPIO"
    echo -e "  ${O}[✓] Módulos adicionados.${R}"
    echo -e "  ${S}Regenerando initramfs...${R}"
    sudo mkinitcpio -P
    echo -e "  ${O}[✓] Initramfs regenerado.${R}"
fi

echo ""

# ══════════════════════════════════════════════════════════════
# 3. modprobe — nvidia_drm modeset
# ══════════════════════════════════════════════════════════════

echo -e "  ${F}[3/4] Configurando nvidia-drm modeset${R}"

MODPROBE_CONF="/etc/modprobe.d/nvidia.conf"
if [ -f "$MODPROBE_CONF" ] && grep -q "modeset=1" "$MODPROBE_CONF" 2>/dev/null; then
    echo -e "  ${S}[~] nvidia-drm modeset já configurado.${R}"
else
    echo "options nvidia_drm modeset=1 fbdev=1" | sudo tee "$MODPROBE_CONF" > /dev/null
    echo -e "  ${O}[✓] /etc/modprobe.d/nvidia.conf criado.${R}"
fi

echo ""

# ══════════════════════════════════════════════════════════════
# 4. Variáveis de ambiente no Hyprland
# ══════════════════════════════════════════════════════════════

echo -e "  ${F}[4/4] Ativando variáveis NVIDIA no Hyprland e stoa-env${R}"

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

echo ""

# ══════════════════════════════════════════════════════════════
# Fim
# ══════════════════════════════════════════════════════════════

echo -e "  ${B}╔══════════════════════════════════════════════════════╗${R}"
echo -e "  ${B}║     NVIDIA + AMD configurado!                        ║${R}"
echo -e "  ${B}╚══════════════════════════════════════════════════════╝${R}"
echo ""
echo -e "  ${F}Pacotes instalados:${R}"
echo -e "  ${S}  nvidia, nvidia-utils, nvidia-settings${R}"
echo -e "  ${S}  libva-nvidia-driver (VA-API para NVIDIA)${R}"
echo -e "  ${S}  amd-ucode (microcode do processador)${R}"
echo ""
echo -e "  ${F}Configurações aplicadas:${R}"
echo -e "  ${S}  /etc/mkinitcpio.conf — módulos early KMS${R}"
echo -e "  ${S}  /etc/modprobe.d/nvidia.conf — DRM modeset + fbdev${R}"
echo -e "  ${S}  hyprland.conf — env vars NVIDIA/Wayland${R}"
echo -e "  ${S}  stoa-env.sh — env vars NVIDIA (login shell)${R}"
echo ""
echo -e "  ${T}Reinicie o sistema para aplicar as mudanças.${R}"
echo ""
echo -e "  ${O}\"Suporta e abstém-te.\" — Epicteto${R}"
echo ""
