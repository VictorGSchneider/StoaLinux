# StoaLinux

Dotfiles estoicos para Arch Linux. Uma personalização minimalista inspirada na filosofia estoica, com cores de mármore romano, bronze, pergaminho e pedra.

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
| Alacritty | `alacritty/alacritty.toml` | Terminal com paleta estoica |
| i3wm | `i3/config` | WM com workspaces em numerais romanos |
| i3status | `i3/i3status.conf` | Barra de status minimalista |
| Neovim | `nvim/init.vim` | Editor com tema `stoa` |
| Colorscheme | `nvim/colors/stoa.vim` | Tema de cores para Neovim |
| Rofi | `rofi/config.rasi` | Launcher com bordas bronze |
| Dunst | `dunst/dunstrc` | Notificações discretas |
| Picom | `picom/picom.conf` | Compositor com sombras suaves |
| GTK 3.0 | `gtk-3.0/settings.ini` | Configuração GTK dark |
| Neofetch | `neofetch/config.conf` | Fetch com nomes estoicos |
| Zsh | `zsh/.zshrc` | Shell com citações e prompt Ι |
| Bash | `zsh/.bashrc` | Alternativa Bash |
| Stoa Fetch | `scripts/stoa-fetch.sh` | Fetch personalizado com coluna grega |
| Stoa Walls | `scripts/stoa-walls.sh` | Gerador de wallpapers minimalistas |
| Cores | `colors.sh` | Referência central da paleta |

## Instalação

### Opção 1: Arch Linux do zero (live ISO)

Instala Arch Linux mínimo + StoaLinux em um único comando, direto do live ISO:

```bash
# No live ISO do Arch Linux, com internet conectada:
curl -LO https://raw.githubusercontent.com/VictorGSchneider/StoaLinux/main/arch-install.sh
chmod +x arch-install.sh
./arch-install.sh
```

O script faz tudo automaticamente:
- Particiona o disco (GPT: EFI + swap + root)
- Instala o sistema base + todos os pacotes do StoaLinux
- Configura locale, timezone, hostname, GRUB
- Cria usuário com sudo
- Instala os dotfiles estoicos

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
sudo pacman -S alacritty i3-wm i3status rofi dunst picom feh neovim imagemagick
sudo pacman -S ttf-jetbrains-mono ttf-font-awesome papirus-icon-theme
sudo pacman -S pipewire pipewire-pulse wireplumber brightnessctl maim
sudo pacman -S xorg-server xorg-xinit zsh git
```

### Shell

O instalador **não** sobrescreve seu `.zshrc` / `.bashrc`. Adicione manualmente:

```bash
# Zsh
echo 'source ~/StoaLinux/zsh/.zshrc' >> ~/.zshrc

# Bash
echo 'source ~/StoaLinux/zsh/.bashrc' >> ~/.bashrc
```

## Funcionalidades

- **Workspaces em numerais romanos** (I, II, III... X) no i3
- **Citação estoica aleatória** ao abrir o terminal
- **Prompt com coluna grega** (Ι) em bronze com branch git
- **stoa-fetch** — system fetch com arte ASCII de templo grego
- **stoa-walls** — gerador de wallpapers com ImageMagick
- **Navegação vim** (hjkl) no i3wm
- **Tema Neovim completo** com suporte a Treesitter
- **Man pages coloridas** na paleta estoica

## Filosofia do Design

- **Simplicidade** — Nada supérfluo, cada elemento tem propósito
- **Harmonia** — Cores naturais que não cansam os olhos
- **Ordem** — Configuração limpa e bem documentada
- **Virtude** — Funcional antes de bonito

> *"A ordem é a primeira lei do céu."* — Marco Aurélio

## Licença

MIT
