#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Arch Linux Minimal Install                    ║
# ║  "A ação é a marca da sabedoria." — Sêneca                  ║
# ║                                                              ║
# ║  Execute este script a partir do live ISO do Arch Linux.     ║
# ║  Ele instala um Arch mínimo + todos os pacotes do Stoa.     ║
# ╚══════════════════════════════════════════════════════════════╝
#
# PRÉ-REQUISITOS (manuais):
#   1. Dê boot pelo ISO do Arch Linux
#   2. Conecte à internet (iwctl ou cabo ethernet)
#   3. Particione, formate e monte os discos manualmente:
#        - Partição EFI montada em /mnt/boot/efi (ou /mnt/boot)
#        - Partição root montada em /mnt
#        - Swap ativado (opcional)
#   4. Baixe e execute:
#        curl -LO https://raw.githubusercontent.com/VictorGSchneider/StoaLinux/main/arch-install.sh
#        chmod +x arch-install.sh
#        ./arch-install.sh
#
# O script NÃO faz:
#   - Particionamento (faça manualmente com fdisk/cfdisk/gdisk)
#   - Criação de usuário (faça manualmente após o reboot)
#
# O script FAZ:
#   - pacstrap com base + todos os pacotes do StoaLinux
#   - Configuração de locale, timezone, hostname
#   - Instalação do rEFInd boot manager
#   - Clonagem e instalação dos dotfiles StoaLinux

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
echo -e "  ${B}║     STOA LINUX — Arch Linux Installer                ║${R}"
echo -e "  ${B}║     Hyprland (Wayland) + i3 (Xorg) fallback          ║${R}"
echo -e "  ${B}╚══════════════════════════════════════════════════════╝${R}"
echo ""

# ── Verificar root ──
if [ "$(id -u)" -ne 0 ]; then
    echo -e "  ${T}[!] Execute como root (live ISO).${R}"
    exit 1
fi

# ── Verificar conexão ──
echo -e "  ${S}Verificando conexão com a internet...${R}"
if ! ping -c 1 archlinux.org &>/dev/null; then
    echo -e "  ${T}[!] Sem conexão. Conecte via:${R}"
    echo -e "  ${S}    Wi-Fi: iwctl station wlan0 connect NOME_DA_REDE${R}"
    echo -e "  ${S}    Cabo:  dhcpcd${R}"
    exit 1
fi
echo -e "  ${O}[✓] Conectado.${R}"
echo ""

# ── Verificar que /mnt está montado ──
if ! mountpoint -q /mnt; then
    echo -e "  ${T}[!] /mnt não está montado.${R}"
    echo -e "  ${S}Particione e monte os discos antes de executar este script:${R}"
    echo ""
    echo -e "  ${F}Exemplo com cfdisk + ext4:${R}"
    echo -e "  ${S}  cfdisk /dev/sda              # criar partições GPT${R}"
    echo -e "  ${S}  mkfs.fat -F 32 /dev/sda1     # EFI (512M)${R}"
    echo -e "  ${S}  mkfs.ext4 /dev/sda2           # Root${R}"
    echo -e "  ${S}  mount /dev/sda2 /mnt${R}"
    echo -e "  ${S}  mkdir -p /mnt/boot/efi${R}"
    echo -e "  ${S}  mount /dev/sda1 /mnt/boot/efi${R}"
    echo ""
    exit 1
fi
echo -e "  ${O}[✓] /mnt montado.${R}"

# Detectar partição EFI
EFI_DIR=""
if mountpoint -q /mnt/boot/efi 2>/dev/null; then
    EFI_DIR="/boot/efi"
elif mountpoint -q /mnt/boot 2>/dev/null; then
    EFI_DIR="/boot"
else
    echo -e "  ${T}[!] Partição EFI não encontrada em /mnt/boot/efi ou /mnt/boot.${R}"
    echo -e "  ${S}Monte a partição EFI antes de continuar.${R}"
    exit 1
fi
echo -e "  ${O}[✓] EFI detectada em ${EFI_DIR}.${R}"
echo ""

# ── Layout de partições ──
echo -e "  ${F}Layout atual:${R}"
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT | grep -E "/mnt|NAME"
echo ""

read -rp "  Layout correto? (s/n): " CONFIRM
if [ "$CONFIRM" != "s" ]; then
    echo -e "  ${S}Ajuste as partições e execute novamente.${R}"
    exit 0
fi

# ── Configurações do sistema ──
echo ""
echo -e "  ${F}Configuração do sistema:${R}"
echo ""

read -rp "  Hostname [stoa]: " HOSTNAME
HOSTNAME="${HOSTNAME:-stoa}"

read -rp "  Timezone [America/Sao_Paulo]: " TIMEZONE
TIMEZONE="${TIMEZONE:-America/Sao_Paulo}"

read -rp "  Locale [pt_BR.UTF-8]: " LOCALE
LOCALE="${LOCALE:-pt_BR.UTF-8}"

echo ""
echo -e "  ${F}Iniciando instalação...${R}"
echo ""

# ══════════════════════════════════════════════════════════════
# FASE 1: Pacstrap
# ══════════════════════════════════════════════════════════════

echo -e "  ${B}[1/5] Instalando sistema base + pacotes StoaLinux...${R}"

# Base
BASE_PKGS="base linux linux-firmware sudo"

# Rede
NET_PKGS="networkmanager"

# Boot — rEFInd
BOOT_PKGS="refind efibootmgr"

# Hyprland (Wayland — primário)
WAYLAND_PKGS="hyprland waybar swaybg xdg-desktop-portal-hyprland"

# i3 (Xorg — fallback)
XORG_PKGS="i3-wm i3status xorg-server xorg-xinit picom"

# Launcher, notificações (funcionam em ambos)
UI_PKGS="rofi dunst"

# Terminal e editor
APP_PKGS="alacritty neovim"

# Screenshot — Wayland (grim+slurp) e Xorg (maim)
SCREENSHOT_PKGS="grim slurp maim"

# Wallpaper — feh para Xorg (swaybg já está nos Wayland pkgs)
WALL_PKGS="feh imagemagick"

# Fontes e tema
FONT_PKGS="ttf-jetbrains-mono ttf-font-awesome papirus-icon-theme"

# Áudio e utilidades
UTIL_PKGS="pipewire pipewire-pulse wireplumber brightnessctl"

# Extras
EXTRA_PKGS="git zsh"

pacstrap -K /mnt \
    $BASE_PKGS $NET_PKGS $BOOT_PKGS \
    $WAYLAND_PKGS $XORG_PKGS $UI_PKGS \
    $APP_PKGS $SCREENSHOT_PKGS $WALL_PKGS \
    $FONT_PKGS $UTIL_PKGS $EXTRA_PKGS

echo -e "  ${O}[✓] Pacotes instalados.${R}"

# ══════════════════════════════════════════════════════════════
# FASE 2: Configuração do sistema
# ══════════════════════════════════════════════════════════════

echo -e "  ${B}[2/5] Configurando sistema...${R}"

# fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Timezone
arch-chroot /mnt ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
arch-chroot /mnt hwclock --systohc

# Locale
LOCALE_SHORT="${LOCALE%.*}"
echo "en_US.UTF-8 UTF-8" >> /mnt/etc/locale.gen
echo "${LOCALE} UTF-8" >> /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
echo "LANG=${LOCALE}" > /mnt/etc/locale.conf

# Hostname
echo "$HOSTNAME" > /mnt/etc/hostname
cat > /mnt/etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
HOSTS

echo -e "  ${O}[✓] Sistema configurado.${R}"

# ══════════════════════════════════════════════════════════════
# FASE 3: rEFInd Boot Manager
# ══════════════════════════════════════════════════════════════

echo -e "  ${B}[3/5] Instalando rEFInd...${R}"

arch-chroot /mnt refind-install --usedefault "${EFI_DIR}"

# Detectar partição root e gerar refind_linux.conf
ROOT_UUID=$(findmnt -n -o UUID /mnt)
cat > /mnt/boot/refind_linux.conf <<REFIND
"Boot with defaults"    "root=UUID=${ROOT_UUID} rw quiet"
"Boot with logging"     "root=UUID=${ROOT_UUID} rw loglevel=3"
REFIND

echo -e "  ${O}[✓] rEFInd instalado.${R}"

# ══════════════════════════════════════════════════════════════
# FASE 4: Serviços
# ══════════════════════════════════════════════════════════════

echo -e "  ${B}[4/5] Habilitando serviços...${R}"

arch-chroot /mnt systemctl enable NetworkManager

# Sudo para grupo wheel
echo "%wheel ALL=(ALL:ALL) ALL" > /mnt/etc/sudoers.d/wheel

echo -e "  ${O}[✓] Serviços habilitados.${R}"

# ══════════════════════════════════════════════════════════════
# FASE 5: Clonar StoaLinux para /etc/skel
# ══════════════════════════════════════════════════════════════

echo -e "  ${B}[5/5] Preparando StoaLinux em /etc/skel...${R}"

# Clonar para /etc/skel para que novos usuários recebam os dotfiles
arch-chroot /mnt git clone https://github.com/VictorGSchneider/StoaLinux.git /etc/skel/StoaLinux

# Executar install.sh em contexto do skel (links apontam para ~/StoaLinux)
SKEL="/mnt/etc/skel"
CONFIG="${SKEL}/.config"
mkdir -p "${CONFIG}/hypr" "${CONFIG}/waybar" "${CONFIG}/i3" \
         "${CONFIG}/alacritty" "${CONFIG}/nvim/colors" \
         "${CONFIG}/rofi" "${CONFIG}/dunst" "${CONFIG}/picom" \
         "${CONFIG}/neofetch" "${CONFIG}/gtk-3.0" \
         "${CONFIG}/stoa/wallpapers" "${SKEL}/.local/bin"

STOA="${SKEL}/StoaLinux"

# Hyprland (primário)
ln -sf ~/StoaLinux/hyprland/hyprland.conf "${CONFIG}/hypr/hyprland.conf"

# Waybar
ln -sf ~/StoaLinux/waybar/config "${CONFIG}/waybar/config"
ln -sf ~/StoaLinux/waybar/style.css "${CONFIG}/waybar/style.css"

# i3 (fallback Xorg)
ln -sf ~/StoaLinux/i3/config "${CONFIG}/i3/config"
ln -sf ~/StoaLinux/i3/i3status.conf "${CONFIG}/i3/i3status.conf"

# Picom (Xorg only)
ln -sf ~/StoaLinux/picom/picom.conf "${CONFIG}/picom/picom.conf"

# Terminal e editor
ln -sf ~/StoaLinux/alacritty/alacritty.toml "${CONFIG}/alacritty/alacritty.toml"
ln -sf ~/StoaLinux/nvim/init.vim "${CONFIG}/nvim/init.vim"
ln -sf ~/StoaLinux/nvim/colors/stoa.vim "${CONFIG}/nvim/colors/stoa.vim"

# UI
ln -sf ~/StoaLinux/rofi/config.rasi "${CONFIG}/rofi/config.rasi"
ln -sf ~/StoaLinux/dunst/dunstrc "${CONFIG}/dunst/dunstrc"

# Outros
ln -sf ~/StoaLinux/neofetch/config.conf "${CONFIG}/neofetch/config.conf"
ln -sf ~/StoaLinux/gtk-3.0/settings.ini "${CONFIG}/gtk-3.0/settings.ini"

# Scripts
ln -sf ~/StoaLinux/scripts/stoa-fetch.sh "${SKEL}/.local/bin/stoa-fetch"
ln -sf ~/StoaLinux/scripts/stoa-walls.sh "${SKEL}/.local/bin/stoa-walls"

# .xinitrc para fallback Xorg
cat > "${SKEL}/.xinitrc" <<'XINITRC'
#!/bin/sh
exec i3
XINITRC

# Zsh config
echo 'source ~/StoaLinux/zsh/.zshrc' > "${SKEL}/.zshrc"

echo -e "  ${O}[✓] StoaLinux preparado em /etc/skel.${R}"

# ══════════════════════════════════════════════════════════════
# Fim
# ══════════════════════════════════════════════════════════════

echo ""
echo -e "  ${B}╔══════════════════════════════════════════════════════╗${R}"
echo -e "  ${B}║     Instalação concluída!                            ║${R}"
echo -e "  ${B}╚══════════════════════════════════════════════════════╝${R}"
echo ""
echo -e "  ${F}Próximos passos:${R}"
echo ""
echo -e "  ${S}  1. Definir senha do root:${R}"
echo -e "  ${B}     arch-chroot /mnt passwd${R}"
echo ""
echo -e "  ${S}  2. Criar seu usuário:${R}"
echo -e "  ${B}     arch-chroot /mnt useradd -m -G wheel -s /bin/zsh USUARIO${R}"
echo -e "  ${B}     arch-chroot /mnt passwd USUARIO${R}"
echo ""
echo -e "  ${S}  3. Desmontar e reiniciar:${R}"
echo -e "  ${B}     umount -R /mnt${R}"
echo -e "  ${B}     reboot${R}"
echo ""
echo -e "  ${S}  4. Após o login:${R}"
echo -e "  ${B}     Hyprland (Wayland):  Hyprland${R}"
echo -e "  ${B}     i3 (Xorg fallback):  startx${R}"
echo ""
echo -e "  ${O}\"O caminho do sábio está preparado.\" — Sêneca${R}"
echo ""
