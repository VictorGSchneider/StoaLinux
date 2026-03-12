# StoaLinux

Dotfiles estoicos para Arch Linux. Uma personalização minimalista inspirada na filosofia estoica, com cores de mármore romano, bronze, pergaminho e pedra.

**Hyprland (Wayland)** como compositor primário, **i3 (Xorg)** como fallback, **rEFInd** como boot manager.

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
| GTK 3.0 | `gtk-3.0/settings.ini` | Configuração GTK dark |
| Neofetch | `neofetch/config.conf` | Fetch com nomes estoicos |
| Zsh | `zsh/.zshrc` | Shell com citações e prompt Ι |
| Bash | `zsh/.bashrc` | Alternativa Bash |
| Stoa Fetch | `scripts/stoa-fetch.sh` | Fetch personalizado com coluna grega |
| Stoa Walls | `scripts/stoa-walls.sh` | Gerador de wallpapers minimalistas |
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

# Comum
sudo pacman -S alacritty neovim rofi dunst imagemagick brightnessctl
sudo pacman -S pipewire pipewire-pulse wireplumber
sudo pacman -S ttf-jetbrains-mono ttf-font-awesome papirus-icon-theme
sudo pacman -S zsh git
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

## Funcionalidades

- **Hyprland** como compositor Wayland primário com animações suaves
- **i3wm** como fallback Xorg com mesmos atalhos
- **rEFInd** boot manager (substituindo GRUB)
- **Workspaces em numerais romanos** (I, II, III... X)
- **Citação estoica aleatória** ao abrir o terminal
- **Prompt com coluna grega** (Ι) em bronze com branch git
- **stoa-fetch** — system fetch com arte ASCII de templo grego
- **stoa-walls** — gerador de wallpapers com ImageMagick
- **Navegação vim** (hjkl) em Hyprland e i3
- **Tema Neovim completo** com suporte a Treesitter
- **Man pages coloridas** na paleta estoica
- **Screenshot** — grim+slurp (Wayland) / maim (Xorg)

## Filosofia do Design

- **Simplicidade** — Nada supérfluo, cada elemento tem propósito
- **Harmonia** — Cores naturais que não cansam os olhos
- **Ordem** — Configuração limpa e bem documentada
- **Virtude** — Funcional antes de bonito

> *"A ordem é a primeira lei do céu."* — Marco Aurélio

## Licença

MIT
