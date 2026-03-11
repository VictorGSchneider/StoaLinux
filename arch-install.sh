#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Arch Linux Minimal Install                    ║
# ║  "A ação é a marca da sabedoria." — Sêneca                  ║
# ║                                                              ║
# ║  Execute este script a partir do live ISO do Arch Linux.     ║
# ║  Ele instala um Arch mínimo + todos os pacotes do Stoa.     ║
# ╚══════════════════════════════════════════════════════════════╝
#
# USO:
#   1. Dê boot pelo ISO do Arch Linux
#   2. Conecte à internet (iwctl ou cabo ethernet)
#   3. curl -LO https://raw.githubusercontent.com/VictorGSchneider/StoaLinux/main/arch-install.sh
#   4. chmod +x arch-install.sh
#   5. ./arch-install.sh
#
# O script vai:
#   - Particionar o disco (GPT: EFI + swap + root)
#   - Instalar base system + pacotes do StoaLinux
#   - Configurar locale, timezone, hostname, bootloader
#   - Criar usuário e instalar dotfiles
#
# ⚠  ATENÇÃO: Este script APAGA TODOS OS DADOS do disco selecionado!

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
echo -e "  ${B}║     Instalação mínima com dotfiles estoicos          ║${R}"
echo -e "  ${B}╚══════════════════════════════════════════════════════╝${R}"
echo ""

# ── Verificar se está no live ISO ──
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

# ── Listar discos ──
echo -e "  ${F}Discos disponíveis:${R}"
echo ""
lsblk -d -o NAME,SIZE,MODEL | grep -v "loop\|sr\|NAME" | while read -r line; do
    echo -e "  ${S}  ${line}${R}"
done
echo ""

# ── Selecionar disco ──
read -rp "  Disco para instalar (ex: sda, nvme0n1): " DISK_NAME
DISK="/dev/${DISK_NAME}"

if [ ! -b "$DISK" ]; then
    echo -e "  ${T}[!] Disco ${DISK} não encontrado.${R}"
    exit 1
fi

echo ""
echo -e "  ${T}╔══════════════════════════════════════════════════════╗${R}"
echo -e "  ${T}║  ATENÇÃO: TODOS OS DADOS em ${DISK} serão APAGADOS!  ${R}"
echo -e "  ${T}╚══════════════════════════════════════════════════════╝${R}"
echo ""
read -rp "  Continuar? (sim/não): " CONFIRM
if [ "$CONFIRM" != "sim" ]; then
    echo -e "  ${S}Instalação cancelada.${R}"
    exit 0
fi

# ── Configurações do sistema ──
echo ""
echo -e "  ${F}Configuração do sistema:${R}"
echo ""

read -rp "  Hostname (ex: stoa): " HOSTNAME
HOSTNAME="${HOSTNAME:-stoa}"

read -rp "  Nome do usuário: " USERNAME
if [ -z "$USERNAME" ]; then
    echo -e "  ${T}[!] Nome de usuário obrigatório.${R}"
    exit 1
fi

read -rsp "  Senha do usuário: " USER_PASS
echo ""
read -rsp "  Confirme a senha: " USER_PASS2
echo ""

if [ "$USER_PASS" != "$USER_PASS2" ]; then
    echo -e "  ${T}[!] Senhas não conferem.${R}"
    exit 1
fi

read -rp "  Timezone (ex: America/Sao_Paulo): " TIMEZONE
TIMEZONE="${TIMEZONE:-America/Sao_Paulo}"

read -rp "  Tamanho do swap em GB (ex: 4, 0 para sem swap): " SWAP_SIZE
SWAP_SIZE="${SWAP_SIZE:-4}"

# ── Shell preferido ──
echo ""
echo -e "  ${F}Shell:${R}"
echo -e "  ${S}  1) zsh (recomendado)${R}"
echo -e "  ${S}  2) bash${R}"
read -rp "  Escolha [1]: " SHELL_CHOICE
SHELL_CHOICE="${SHELL_CHOICE:-1}"

SHELL_PKG="zsh"
SHELL_BIN="/bin/zsh"
if [ "$SHELL_CHOICE" = "2" ]; then
    SHELL_PKG="bash"
    SHELL_BIN="/bin/bash"
fi

echo ""
echo -e "  ${F}Iniciando instalação...${R}"
echo ""

# ══════════════════════════════════════════════════════════════
# FASE 1: Particionamento
# ══════════════════════════════════════════════════════════════

echo -e "  ${B}[1/7] Particionando ${DISK}...${R}"

# Detectar se é NVMe (partições: p1, p2) ou SATA (1, 2)
if [[ "$DISK" == *"nvme"* ]]; then
    PART_PREFIX="${DISK}p"
else
    PART_PREFIX="${DISK}"
fi

# Limpar tabela de partições
wipefs -af "$DISK" &>/dev/null
sgdisk -Z "$DISK" &>/dev/null

if [ "$SWAP_SIZE" -gt 0 ] 2>/dev/null; then
    # GPT: EFI (512M) + Swap + Root
    sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI" "$DISK"
    sgdisk -n 2:0:+${SWAP_SIZE}G -t 2:8200 -c 2:"Swap" "$DISK"
    sgdisk -n 3:0:0 -t 3:8300 -c 3:"Root" "$DISK"

    PART_EFI="${PART_PREFIX}1"
    PART_SWAP="${PART_PREFIX}2"
    PART_ROOT="${PART_PREFIX}3"
else
    # GPT: EFI (512M) + Root
    sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI" "$DISK"
    sgdisk -n 2:0:0 -t 2:8300 -c 2:"Root" "$DISK"

    PART_EFI="${PART_PREFIX}1"
    PART_SWAP=""
    PART_ROOT="${PART_PREFIX}2"
fi

# Esperar dispositivos
sleep 2
partprobe "$DISK" 2>/dev/null || true

echo -e "  ${O}[✓] Particionamento concluído.${R}"

# ══════════════════════════════════════════════════════════════
# FASE 2: Formatação e Montagem
# ══════════════════════════════════════════════════════════════

echo -e "  ${B}[2/7] Formatando e montando...${R}"

mkfs.fat -F 32 "$PART_EFI"
mkfs.ext4 -F "$PART_ROOT"

if [ -n "$PART_SWAP" ]; then
    mkswap "$PART_SWAP"
    swapon "$PART_SWAP"
fi

mount "$PART_ROOT" /mnt
mkdir -p /mnt/boot/efi
mount "$PART_EFI" /mnt/boot/efi

echo -e "  ${O}[✓] Formatado e montado.${R}"

# ══════════════════════════════════════════════════════════════
# FASE 3: Instalação base + pacotes StoaLinux
# ══════════════════════════════════════════════════════════════

echo -e "  ${B}[3/7] Instalando sistema base + pacotes StoaLinux...${R}"

# Pacotes base mínimos
BASE_PKGS="base linux linux-firmware"

# Utilitários essenciais
UTIL_PKGS="sudo networkmanager grub efibootmgr os-prober"

# StoaLinux - Window Manager e componentes
STOA_WM="i3-wm i3status rofi dunst picom"

# StoaLinux - Terminal e editor
STOA_APPS="alacritty neovim feh"

# StoaLinux - Fontes
STOA_FONTS="ttf-jetbrains-mono ttf-font-awesome"

# StoaLinux - Áudio e utilidades
STOA_UTILS="pipewire pipewire-pulse wireplumber brightnessctl maim xorg-server xorg-xinit"

# StoaLinux - Ferramentas extras
STOA_EXTRA="git imagemagick ${SHELL_PKG}"

# GTK theme
STOA_GTK="papirus-icon-theme"

pacstrap -K /mnt $BASE_PKGS $UTIL_PKGS $STOA_WM $STOA_APPS $STOA_FONTS $STOA_UTILS $STOA_EXTRA $STOA_GTK

echo -e "  ${O}[✓] Pacotes instalados.${R}"

# ══════════════════════════════════════════════════════════════
# FASE 4: Configuração do sistema
# ══════════════════════════════════════════════════════════════

echo -e "  ${B}[4/7] Configurando sistema...${R}"

# fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Timezone
arch-chroot /mnt ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
arch-chroot /mnt hwclock --systohc

# Locale
echo "en_US.UTF-8 UTF-8" >> /mnt/etc/locale.gen
echo "pt_BR.UTF-8 UTF-8" >> /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
echo "LANG=pt_BR.UTF-8" > /mnt/etc/locale.conf

# Hostname
echo "$HOSTNAME" > /mnt/etc/hostname
cat > /mnt/etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
HOSTS

echo -e "  ${O}[✓] Sistema configurado.${R}"

# ══════════════════════════════════════════════════════════════
# FASE 5: Bootloader (GRUB EFI)
# ══════════════════════════════════════════════════════════════

echo -e "  ${B}[5/7] Instalando bootloader (GRUB)...${R}"

arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=StoaLinux
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

echo -e "  ${O}[✓] GRUB instalado.${R}"

# ══════════════════════════════════════════════════════════════
# FASE 6: Usuário e serviços
# ══════════════════════════════════════════════════════════════

echo -e "  ${B}[6/7] Criando usuário e habilitando serviços...${R}"

# Criar usuário
arch-chroot /mnt useradd -m -G wheel -s "$SHELL_BIN" "$USERNAME"
echo "${USERNAME}:${USER_PASS}" | arch-chroot /mnt chpasswd

# Sudo para grupo wheel
echo "%wheel ALL=(ALL:ALL) ALL" > /mnt/etc/sudoers.d/wheel

# Habilitar serviços
arch-chroot /mnt systemctl enable NetworkManager

# .xinitrc para iniciar i3
cat > "/mnt/home/${USERNAME}/.xinitrc" <<'XINITRC'
#!/bin/sh
exec i3
XINITRC
arch-chroot /mnt chown "${USERNAME}:${USERNAME}" "/home/${USERNAME}/.xinitrc"

echo -e "  ${O}[✓] Usuário criado e serviços habilitados.${R}"

# ══════════════════════════════════════════════════════════════
# FASE 7: Instalar StoaLinux dotfiles
# ══════════════════════════════════════════════════════════════

echo -e "  ${B}[7/7] Instalando StoaLinux dotfiles...${R}"

# Clonar repo no home do usuário
arch-chroot /mnt su - "$USERNAME" -c \
    "git clone https://github.com/VictorGSchneider/StoaLinux.git ~/StoaLinux"

# Executar instalador de dotfiles
arch-chroot /mnt su - "$USERNAME" -c \
    "cd ~/StoaLinux && chmod +x install.sh && ./install.sh"

# Configurar shell
if [ "$SHELL_CHOICE" = "1" ]; then
    # Zsh
    arch-chroot /mnt su - "$USERNAME" -c \
        "echo 'source ~/StoaLinux/zsh/.zshrc' >> ~/.zshrc"
else
    # Bash
    arch-chroot /mnt su - "$USERNAME" -c \
        "echo 'source ~/StoaLinux/zsh/.bashrc' >> ~/.bashrc"
fi

echo -e "  ${O}[✓] StoaLinux dotfiles instalados.${R}"

# ══════════════════════════════════════════════════════════════
# Fim
# ══════════════════════════════════════════════════════════════

echo ""
echo -e "  ${B}╔══════════════════════════════════════════════════════╗${R}"
echo -e "  ${B}║     Instalação concluída!                            ║${R}"
echo -e "  ${B}╚══════════════════════════════════════════════════════╝${R}"
echo ""
echo -e "  ${F}Próximos passos:${R}"
echo -e "  ${S}  1. umount -R /mnt${R}"
echo -e "  ${S}  2. reboot${R}"
echo -e "  ${S}  3. Login com: ${B}${USERNAME}${R}"
echo -e "  ${S}  4. Iniciar interface: ${B}startx${R}"
echo ""
echo -e "  ${O}\"O caminho do sábio está preparado.\" — Sêneca${R}"
echo ""
