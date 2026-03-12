#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Arch Install                                  ║
# ║  "A ação é a marca da sabedoria." — Sêneca                  ║
# ║                                                              ║
# ║  Usa o archinstall padrão com configuração StoaLinux.        ║
# ║  Discos e usuário são configurados manualmente via TUI.      ║
# ╚══════════════════════════════════════════════════════════════╝
#
# USO (a partir do live ISO do Arch Linux):
#
#   curl -LO https://raw.githubusercontent.com/VictorGSchneider/StoaLinux/main/arch-install.sh
#   chmod +x arch-install.sh
#   ./arch-install.sh
#
# O que acontece:
#   1. Baixa a config JSON do StoaLinux
#   2. Abre o archinstall padrão com os pacotes pré-selecionados
#      → Discos, usuário e senha são escolhidos por VOCÊ na TUI
#      → Bootloader, pacotes, áudio, locale já vêm configurados
#   3. Após o archinstall terminar, instala os dotfiles StoaLinux

set -e

# ── Cores ──
B='\033[38;2;196;154;92m'
S='\033[38;2;110;106;98m'
F='\033[38;2;212;207;196m'
O='\033[38;2;138;154;108m'
T='\033[38;2;179;107;90m'
R='\033[0m'

# ── Banner ──
echo ""
echo -e "  ${B}╔══════════════════════════════════════════════════════╗${R}"
echo -e "  ${B}║     STOA LINUX — Arch Installer                      ║${R}"
echo -e "  ${B}║     archinstall + Hyprland/Wayland + i3/Xorg          ║${R}"
echo -e "  ${B}╚══════════════════════════════════════════════════════╝${R}"
echo ""

# ── Verificar root ──
if [ "$(id -u)" -ne 0 ]; then
    echo -e "  ${T}[!] Execute como root (live ISO).${R}"
    exit 1
fi

# ── Verificar conexão ──
echo -e "  ${S}Verificando conexão...${R}"
if ! ping -c 1 archlinux.org &>/dev/null; then
    echo -e "  ${T}[!] Sem conexão. Conecte via:${R}"
    echo -e "  ${S}    Wi-Fi:  iwctl station wlan0 connect NOME_DA_REDE${R}"
    echo -e "  ${S}    Cabo:   dhcpcd${R}"
    exit 1
fi
echo -e "  ${O}[✓] Conectado.${R}"
echo ""

# ══════════════════════════════════════════════════════════════
# FASE 1: Baixar config do StoaLinux
# ══════════════════════════════════════════════════════════════

STOA_REPO="https://raw.githubusercontent.com/VictorGSchneider/StoaLinux/main"
CONFIG_DIR="/tmp/stoa-archinstall"
mkdir -p "$CONFIG_DIR"

echo -e "  ${B}[1/3] Baixando configuração StoaLinux...${R}"
curl -sL "${STOA_REPO}/archinstall/user_configuration.json" -o "${CONFIG_DIR}/user_configuration.json"
echo -e "  ${O}[✓] Config baixada.${R}"
echo ""

# ── Mostrar o que vem pré-configurado ──
echo -e "  ${F}Configuração pré-definida pelo StoaLinux:${R}"
echo -e "  ${S}  Bootloader:  systemd-boot (efistub)${R}"
echo -e "  ${S}  Áudio:       PipeWire${R}"
echo -e "  ${S}  Rede:        NetworkManager${R}"
echo -e "  ${S}  Locale:      pt_BR.UTF-8 / teclado br${R}"
echo -e "  ${S}  Timezone:    America/Sao_Paulo${R}"
echo -e "  ${S}  Pacotes:     Hyprland, Waybar, i3, Alacritty, Neovim, Rofi...${R}"
echo ""
echo -e "  ${F}Você configura na TUI do archinstall:${R}"
echo -e "  ${B}  → Discos (particionamento e formatação)${R}"
echo -e "  ${B}  → Usuário e senha${R}"
echo -e "  ${B}  → Driver de vídeo (se necessário)${R}"
echo ""
echo -e "  ${S}Todos os campos podem ser alterados na TUI.${R}"
echo ""

read -rp "  Iniciar archinstall? (s/n) [s]: " START
START="${START:-s}"
if [ "$START" != "s" ]; then
    echo -e "  ${S}Cancelado.${R}"
    exit 0
fi

# ══════════════════════════════════════════════════════════════
# FASE 2: Executar archinstall
# ══════════════════════════════════════════════════════════════

echo ""
echo -e "  ${B}[2/3] Iniciando archinstall...${R}"
echo -e "  ${S}Configure discos, usuário e driver de vídeo na TUI.${R}"
echo ""

archinstall --config "${CONFIG_DIR}/user_configuration.json"

# ══════════════════════════════════════════════════════════════
# FASE 3: Instalar dotfiles StoaLinux via chroot
# ══════════════════════════════════════════════════════════════

echo ""
echo -e "  ${B}[3/3] Instalando dotfiles StoaLinux...${R}"

# Detectar ponto de montagem do archinstall
INSTALL_ROOT="/mnt/archinstall"
if [ ! -d "$INSTALL_ROOT" ] || ! mountpoint -q "$INSTALL_ROOT" 2>/dev/null; then
    INSTALL_ROOT="/mnt"
fi

if ! mountpoint -q "$INSTALL_ROOT" 2>/dev/null; then
    echo -e "  ${T}[!] Sistema não encontrado montado.${R}"
    echo -e "  ${S}Execute o post-install.sh após o primeiro boot.${R}"
    exit 0
fi

# Detectar o primeiro usuário criado
CREATED_USER=""
for userdir in "${INSTALL_ROOT}/home"/*/; do
    if [ -d "$userdir" ]; then
        CREATED_USER=$(basename "$userdir")
        break
    fi
done

if [ -z "$CREATED_USER" ]; then
    echo -e "  ${T}[!] Nenhum usuário encontrado. Execute post-install.sh após o boot.${R}"
    exit 0
fi

echo -e "  ${S}Usuário detectado: ${B}${CREATED_USER}${R}"

# Clonar StoaLinux no home do usuário
arch-chroot "$INSTALL_ROOT" su - "$CREATED_USER" -c \
    "git clone https://github.com/VictorGSchneider/StoaLinux.git ~/StoaLinux" 2>/dev/null || true

# Executar install.sh (cria symlinks dos dotfiles)
arch-chroot "$INSTALL_ROOT" su - "$CREATED_USER" -c \
    "cd ~/StoaLinux && chmod +x install.sh && bash install.sh" 2>/dev/null || true

# Configurar zsh
arch-chroot "$INSTALL_ROOT" su - "$CREATED_USER" -c \
    "grep -q StoaLinux ~/.zshrc 2>/dev/null || echo 'source ~/StoaLinux/zsh/.zshrc' >> ~/.zshrc" 2>/dev/null || true

# .xinitrc para fallback Xorg
arch-chroot "$INSTALL_ROOT" su - "$CREATED_USER" -c \
    "[ -f ~/.xinitrc ] || echo 'exec i3' > ~/.xinitrc" 2>/dev/null || true

echo -e "  ${O}[✓] Dotfiles instalados para ${CREATED_USER}.${R}"

# ══════════════════════════════════════════════════════════════
# Fim
# ══════════════════════════════════════════════════════════════

echo ""
echo -e "  ${B}╔══════════════════════════════════════════════════════╗${R}"
echo -e "  ${B}║     Instalação concluída!                            ║${R}"
echo -e "  ${B}╚══════════════════════════════════════════════════════╝${R}"
echo ""
echo -e "  ${F}Após o reboot, faça login e inicie:${R}"
echo -e "  ${B}  Hyprland (Wayland):  Hyprland${R}"
echo -e "  ${B}  i3 (Xorg fallback):  startx${R}"
echo ""
echo -e "  ${O}\"O caminho do sábio está preparado.\" — Sêneca${R}"
echo ""
