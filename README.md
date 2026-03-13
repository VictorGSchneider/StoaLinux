# StoaLinux

Dotfiles estoicos para Arch Linux. Uma personalização minimalista inspirada na filosofia estoica, com cores de mármore romano, bronze, pergaminho e pedra.

**Hyprland (Wayland)** como compositor primário, **i3 (Xorg)** como fallback. Apps minimalistas, Brave Browser, aparência unificada GTK/Qt.

> *"A felicidade depende da qualidade dos teus pensamentos."* — Marco Aurélio

## Paleta de Cores

| Cor | Hex | Inspiração |
|-----|-----|------------|
| Background | `#211e19` | Obsidiana / Carvão |
| Foreground | `#d4cfc4` | Mármore claro |
| Bronze | `#c49a5c` | Bronze romano |
| Ouro | `#d4a84b` | Ouro imperial |
| Pergaminho | `#c4b08a` | Pergaminho antigo |
| Oliva | `#8a9a6c` | Folha de louro |
| Terracota | `#b36b5a` | Terracota romana |
| Azul | `#5a7a8a` | Mar Mediterrâneo |
| Pedra | `#6e6a62` | Pedra polida |

## Componentes

| Componente | Arquivo | Descrição |
|------------|---------|-----------|
| **Hyprland** | `hyprland/hyprland.conf` | Compositor Wayland (primário) |
| **Waybar** | `waybar/config`, `waybar/style.css` | Barra de status Wayland |
| i3wm | `i3/config` | WM Xorg (fallback) |
| i3status | `i3/i3status.conf` | Barra de status Xorg |
| Picom | `picom/picom.conf` | Compositor Xorg (fallback) |
| Alacritty | `alacritty/alacritty.toml` | Terminal com paleta estoica |
| Neovim | `nvim/init.vim` | Editor com tema `stoa` |
| Colorscheme | `nvim/colors/stoa.vim` | Tema de cores para Neovim |
| Rofi | `rofi/config.rasi` | Launcher com bordas bronze |
| Dunst | `dunst/dunstrc` | Notificações discretas |
| **Brave** | (pacote AUR) | Browser padrão |
| **Obsidian** | (pacote AUR) | Notas e segundo cérebro |
| **eww** | `eww/eww.yuck`, `eww/eww.scss` | Widget Memento Mori |
| **Zathura** | `zathura/zathurarc` | Leitor PDF com tema estoico |
| **mpv** | `mpv/mpv.conf` | Player de vídeo minimalista |
| **imv** | `imv/config` | Visualizador de imagens (Wayland) |
| **lf** | `lf/lfrc` | File manager vim-style |
| **btop** | `btop/btop.conf` | Monitor do sistema |
| GTK 3.0 | `gtk-3.0/settings.ini` | Tema GTK dark |
| GTK 4.0 | `gtk-4.0/settings.ini` | Tema GTK4 dark |
| Qt5/Qt6 | `qt5ct/`, `qt6ct/` | Qt padronizado com GTK (Fusion dark) |
| Environment | `environment/stoa-env.sh` | Variáveis de toolkit + apps padrão |
| Neofetch | `neofetch/config.conf` | Fetch com nomes estoicos |
| Zsh | `zsh/.zshrc` | Shell com citações e prompt Ι |
| Bash | `zsh/.bashrc` | Alternativa Bash |
| Stoa Fetch | `scripts/stoa-fetch.sh` | Fetch personalizado com coluna grega |
| Stoa Walls | `scripts/stoa-walls.sh` | Gerador de wallpapers minimalistas |
| Memento Mori | `scripts/stoa-memento.sh` | Toggle do widget Memento Mori |
| Memento Data | `scripts/stoa-memento-data.sh` | Dados JSON para o widget eww |
| NVIDIA Setup | `scripts/stoa-nvidia-setup.sh` | Configuração AMD CPU + NVIDIA GPU |
| Cores | `colors.sh` | Referência central da paleta |

## Instalação

### Opção 1: Arch Linux do zero (live ISO)

Usa o `archinstall` padrão do Arch com uma config pré-definida do StoaLinux:

```bash
# No live ISO, com internet conectada:
curl -LO https://raw.githubusercontent.com/VictorGSchneider/StoaLinux/main/arch-install.sh
chmod +x arch-install.sh
./arch-install.sh
```

O script abre o `archinstall` com pacotes e configurações pré-selecionados. **Você configura na TUI:**
- Discos (particionamento e formatação)
- Usuário e senha
- Driver de vídeo

**Pré-configurado pelo StoaLinux:**
- Pacotes: Hyprland, Waybar, i3, Alacritty, Neovim, Rofi, PipeWire...
- Locale: `pt_BR.UTF-8`, teclado `br`
- Rede: NetworkManager
- Após o archinstall, instala automaticamente os dotfiles

### Opção 2: Arch Linux já instalado (post-install)

Para um Arch já funcional, instala os pacotes e dotfiles:

```bash
git clone https://github.com/VictorGSchneider/StoaLinux.git
cd StoaLinux
chmod +x post-install.sh
./post-install.sh
```

### Opção 3: Apenas dotfiles (pacotes já instalados)

Se já tem os pacotes e quer só os dotfiles:

```bash
git clone https://github.com/VictorGSchneider/StoaLinux.git
cd StoaLinux
chmod +x install.sh
./install.sh
```

### Dependências

```bash
# Wayland (primário)
sudo pacman -S hyprland waybar swaybg xdg-desktop-portal-hyprland grim slurp

# Xorg (fallback)
sudo pacman -S i3-wm i3status xorg-server xorg-xinit picom maim feh

# Apps estoicos
sudo pacman -S alacritty neovim rofi dunst zathura zathura-pdf-mupdf mpv imv lf btop

# Toolkit unification (GTK/Qt)
sudo pacman -S qt5ct qt6ct papirus-icon-theme imagemagick

# Áudio, fontes, extras
sudo pacman -S pipewire pipewire-pulse wireplumber brightnessctl
sudo pacman -S ttf-jetbrains-mono ttf-font-awesome
sudo pacman -S zsh git base-devel

# Widgets
sudo pacman -S eww

# Brave Browser + Obsidian (AUR)
git clone https://aur.archlinux.org/brave-bin.git /tmp/brave-bin
cd /tmp/brave-bin && makepkg -si
git clone https://aur.archlinux.org/obsidian.git /tmp/obsidian
cd /tmp/obsidian && makepkg -si
```

### NVIDIA GPU + AMD CPU

Se você usa processador AMD com placa NVIDIA, execute o script de setup:

```bash
cd StoaLinux
chmod +x scripts/stoa-nvidia-setup.sh
./scripts/stoa-nvidia-setup.sh
```

O script instala e configura:
- `nvidia`, `nvidia-utils`, `nvidia-settings`, `libva-nvidia-driver`
- `amd-ucode` (microcode do processador)
- Módulos early KMS no mkinitcpio (`nvidia nvidia_modeset nvidia_uvm nvidia_drm`)
- `nvidia-drm modeset=1 fbdev=1` via modprobe
- Variáveis de ambiente NVIDIA no Hyprland e stoa-env.sh
```

### Shell

O instalador **não** sobrescreve seu `.zshrc` / `.bashrc`. Adicione manualmente:

```bash
# Zsh
echo 'source ~/StoaLinux/zsh/.zshrc' >> ~/.zshrc

# Bash
echo 'source ~/StoaLinux/zsh/.bashrc' >> ~/.bashrc
```

## Iniciar

```bash
# Hyprland (Wayland — primário)
Hyprland

# i3 (Xorg — fallback)
startx
```

## Atalhos

| Tecla | Ação |
|-------|------|
| `Super+Return` | Terminal (Alacritty) |
| `Super+B` | Browser (Brave) |
| `Super+E` | Arquivos (lf) |
| `Super+N` | Monitor (btop) |
| `Super+D` | Launcher (Rofi) |
| `Super+O` | Notas (Obsidian) |
| `Super+M` | Memento Mori (eww widget) |
| `Super+Q` | Fechar janela |
| `Super+F` | Fullscreen |
| `Super+HJKL` | Navegação vim |
| `Super+1-0` | Workspaces I-X |
| `Print` | Screenshot tela inteira |
| `Super+Print` | Screenshot seleção |

## Funcionalidades

- **Hyprland** como compositor Wayland primário com animações suaves
- **i3wm** como fallback Xorg com mesmos atalhos
- **Brave Browser** como navegador padrão (privacidade + Wayland nativo)
- **Obsidian** como app de notas e segundo cérebro (Markdown)
- **Memento Mori** — widget eww com dias/semanas/anos vividos, progresso do ano e citação estoica
- **Apps estoicos**: zathura (PDF), mpv (vídeo), imv (imagens), lf (arquivos), btop (monitor)
- **Aparência unificada** — GTK e Qt usam mesmo tema escuro, fonte e ícones via qt5ct/qt6ct
- **Workspaces em numerais romanos** (I, II, III... X)
- **Citação estoica aleatória** ao abrir o terminal
- **Prompt com coluna grega** (Ι) em bronze com branch git
- **stoa-fetch** — system fetch com arte ASCII de templo grego
- **stoa-walls** — gerador de wallpapers com ImageMagick
- **Navegação vim** (hjkl) em Hyprland, i3 e lf
- **Tema Neovim completo** com suporte a Treesitter
- **Man pages coloridas** na paleta estoica
- **Screenshot** — grim+slurp (Wayland) / maim (Xorg)
- **XDG MIME** configurado — Brave para web, zathura para PDF, mpv para vídeo, imv para imagens

## Filosofia do Design

- **Simplicidade** — Nada supérfluo, cada elemento tem propósito
- **Harmonia** — Cores naturais que não cansam os olhos
- **Ordem** — Configuração limpa e bem documentada
- **Virtude** — Funcional antes de bonito

> *"A ordem é a primeira lei do céu."* — Marco Aurélio

## Licença

MIT
