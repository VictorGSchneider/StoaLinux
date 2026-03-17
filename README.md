# StoaLinux

Stoic dotfiles for Arch Linux. A minimalist customization inspired by Stoic philosophy, with colors of Roman marble, bronze, parchment, and stone.

**Hyprland (Wayland)** as primary compositor, **i3 (Xorg)** as fallback. Minimalist apps, Brave Browser, unified GTK/Qt appearance.

> *"The happiness of your life depends upon the quality of your thoughts."* — Marcus Aurelius

## Color Palette

| Color | Hex | Inspiration |
|-------|-----|-------------|
| Background | `#211e19` | Obsidian / Charcoal |
| Foreground | `#d4cfc4` | Light marble |
| Bronze | `#c49a5c` | Roman bronze |
| Gold | `#d4a84b` | Imperial gold |
| Parchment | `#c4b08a` | Ancient parchment |
| Olive | `#8a9a6c` | Laurel leaf |
| Terracotta | `#b36b5a` | Roman terracotta |
| Azure | `#5a7a8a` | Mediterranean Sea |
| Stone | `#6e6a62` | Polished stone |

## Components

| Component | File | Description |
|-----------|------|-------------|
| **Hyprland** | `hyprland/hyprland.conf` | Wayland compositor (primary) |
| **Waybar** | `waybar/config`, `waybar/style.css` | Wayland status bar |
| i3wm | `i3/config` | Xorg WM (fallback) |
| i3status | `i3/i3status.conf` | Xorg status bar |
| Picom | `picom/picom.conf` | Xorg compositor (fallback) |
| Alacritty | `alacritty/alacritty.toml` | Terminal with Stoic palette |
| Neovim | `nvim/init.vim` | Editor with `stoa` theme |
| Colorscheme | `nvim/colors/stoa.vim` | Neovim color theme |
| Rofi | `rofi/config.rasi` | Launcher with bronze borders |
| Dunst | `dunst/dunstrc` | Discrete notifications |
| **Brave** | (AUR package) | Default browser |
| **Obsidian** | (AUR package) | Notes and second brain |
| **eww** | `eww/eww.yuck`, `eww/eww.scss` | Memento Mori widget |
| **Zathura** | `zathura/zathurarc` | PDF reader with Stoic theme |
| **mpv** | `mpv/mpv.conf` | Minimalist video player |
| **imv** | `imv/config` | Image viewer (Wayland) |
| **lf** | `lf/lfrc` | Vim-style file manager (terminal) |
| **Thunar** | — | GUI file manager with volume management |
| **btop** | `btop/btop.conf` | System monitor |
| GTK 3.0 | `gtk-3.0/settings.ini` | GTK dark theme |
| GTK 4.0 | `gtk-4.0/settings.ini` | GTK4 dark theme |
| Qt5/Qt6 | `qt5ct/`, `qt6ct/` | Qt standardized with GTK (Fusion dark) |
| Environment | `environment/stoa-env.sh` | Toolkit variables + default apps |
| Neofetch | `neofetch/config.conf` | Fetch with Stoic names |
| Zsh | `zsh/.zshrc` | Shell with quotes and Ι prompt |
| Bash | `zsh/.bashrc` | Bash alternative |
| Stoa Config | `stoa.conf` | Stoa settings (keybinds, etc.) |
| Colors | `colors.sh` | Central palette reference |

## Scripts & Tools

| Script | Description |
|--------|-------------|
| `stoa-fetch` | System fetch with Greek temple ASCII art |
| `stoa-walls` | Minimalist wallpaper generator (ImageMagick) |
| `stoa-memento` | Toggle Memento Mori widget (eww) |
| `stoa-memento-data` | JSON data for widget (days/weeks/years lived) |
| `stoa-gpu-setup` | Automatic CPU + GPU setup (NVIDIA/AMD/Intel) |
| `stoa-keybinds-bar` | Keybinds in Waybar (toggle module) |
| `stoa-osd` | OSD for volume, brightness, CapsLock/NumLock (1% increments) |
| `stoa-clipboard` | Clipboard manager with pinned favorites (wl-clipboard + cliphist + rofi) |
| `stoa-quotes-sync` | Stoic quotes from the internet with playlist rotation |

### Stoatools

Utility tools integrated with the desktop and Thunar file manager:

| Script | Description |
|--------|-------------|
| `stoa-locksmith` | Find which process is locking a file (`lsof` + rofi) |
| `stoa-resize` | Resize multiple images at once with presets (ImageMagick + rofi) |
| `stoa-paste` | Paste clipboard in different formats: plain, UPPERCASE, lowercase, Title Case, snake_case, camelCase, JSON, Markdown |
| `stoa-ocr` | Extract text from screen areas or image files using OCR (`tesseract`) |
| `stoa-rename` | Batch rename files with regex, rofi preview, and conflict protection |

Stoatools with Thunar integration (right-click custom actions):
- **Resize images** — select images in Thunar, right-click → Stoatools: Resize
- **Rename files** — select files, right-click → Stoatools: Rename
- **OCR image** — select an image, right-click → Stoatools: OCR
- **Locksmith** — select a file, right-click → Stoatools: Locksmith

## Installation

### Option 1: Arch Linux from scratch (live ISO)

Uses the standard `archinstall` with a pre-defined StoaLinux config:

```bash
# From the live ISO, with internet connected:
curl -LO https://raw.githubusercontent.com/VictorGSchneider/StoaLinux/main/arch-install.sh
chmod +x arch-install.sh
./arch-install.sh
```

The script opens `archinstall` with pre-selected packages and settings. **You configure in the TUI:**
- Disks (partitioning and formatting)
- User and password
- Video driver

**Pre-configured by StoaLinux:**
- Packages: Hyprland, Waybar, i3, Alacritty, Neovim, Rofi, PipeWire...
- Locale: `pt_BR.UTF-8`, keyboard `br`
- Network: NetworkManager
- After archinstall, automatically installs dotfiles

### Option 2: Existing Arch Linux (post-install)

For an already working Arch, installs packages and dotfiles:

```bash
git clone https://github.com/VictorGSchneider/StoaLinux.git
cd StoaLinux
chmod +x post-install.sh
./post-install.sh
```

### Option 3: Dotfiles only (packages already installed)

If you already have the packages and just want the dotfiles:

```bash
git clone https://github.com/VictorGSchneider/StoaLinux.git
cd StoaLinux
chmod +x install.sh
./install.sh
```

### Dependencies

```bash
# Wayland (primary)
sudo pacman -S hyprland waybar swaybg xdg-desktop-portal-hyprland grim slurp

# Xorg (fallback)
sudo pacman -S i3-wm i3status xorg-server xorg-xinit picom maim feh

# Stoic apps
sudo pacman -S alacritty neovim rofi dunst zathura zathura-pdf-mupdf mpv imv lf btop

# Toolkit unification (GTK/Qt)
sudo pacman -S qt5ct qt6ct papirus-icon-theme imagemagick

# Audio, fonts, extras
sudo pacman -S pipewire pipewire-pulse wireplumber brightnessctl jq curl
sudo pacman -S ttf-jetbrains-mono ttf-font-awesome
sudo pacman -S zsh git base-devel

# Clipboard
sudo pacman -S wl-clipboard cliphist

# Stoatools (OCR, paste, resize, rename, locksmith)
sudo pacman -S tesseract tesseract-data-eng tesseract-data-por lsof wtype

# AUR: Widgets, Browser, Notes, Screenshot editor
yay -S eww-wayland brave-bin obsidian satty
```

### GPU + CPU Setup

After installation, configure GPU drivers and CPU microcode:

```bash
cd StoaLinux
chmod +x scripts/stoa-gpu-setup.sh
./scripts/stoa-gpu-setup.sh
```

The script automatically detects:
- **CPU**: AMD (`amd-ucode`) or Intel (`intel-ucode`)
- **NVIDIA GPU**: picks the correct driver for your generation (`nvidia`, `nvidia-open`, `nvidia-470xx-dkms`)
- **AMD GPU**: `mesa` + `vulkan-radeon` + `libva-mesa-driver`
- **Intel GPU**: `mesa` + `vulkan-intel` + `intel-media-driver`

For NVIDIA, it also configures:
- Early KMS modules in mkinitcpio
- `nvidia-drm modeset=1 fbdev=1` via modprobe
- NVIDIA environment variables in Hyprland and stoa-env.sh

### Shell

The installer does **not** overwrite your `.zshrc` / `.bashrc`. Add manually:

```bash
# Zsh
echo 'source ~/StoaLinux/zsh/.zshrc' >> ~/.zshrc

# Bash
echo 'source ~/StoaLinux/zsh/.bashrc' >> ~/.bashrc
```

## Starting

```bash
# Hyprland (Wayland — primary)
Hyprland

# i3 (Xorg — fallback)
startx
```

## Keybinds

| Key | Action |
|-----|--------|
| `Super+Return` | Terminal (Alacritty) |
| `Super+B` | Browser (Brave) |
| `Super+E` | Files (lf) |
| `Super+Shift+E` | Files (Thunar) |
| `Super+N` | Monitor (btop) |
| `Super+D` | Launcher (Rofi) |
| `Super+O` | Notes (Obsidian) |
| `Super+M` | Memento Mori (eww widget) |
| `Super+V` | Clipboard (history) |
| `Super+Shift+V` | Clipboard (pin/unpin) |
| `Super+Shift+T` | OCR — extract text from screen |
| `Super+Shift+P` | Advanced Paste (formats) |
| `Super+/` | Bar keybinds (toggle) |
| `Super+Q` | Close window |
| `Super+F` | Fullscreen |
| `Super+R` | Resize mode (HJKL) |
| `Super+HJKL` | Vim navigation |
| `Super+Shift+HJKL` | Move window |
| `Super+1-0` | Workspaces I-X |
| `Print` | Screenshot full screen |
| `Super+Print` | Screenshot selection |
| `Scroll on Waybar` | Volume +/- |
| `XF86Audio*` | Volume (OSD) |
| `XF86MonBrightness*` | Brightness (OSD) |

## Features

- **Hyprland** as primary Wayland compositor with smooth animations
- **i3wm** as Xorg fallback with same keybinds
- **Brave Browser** as default browser (privacy + native Wayland)
- **Obsidian** as notes and second brain app (Markdown)
- **Memento Mori** — eww widget with days/weeks/years lived, year progress, and Stoic quote
- **Stoic apps**: zathura (PDF), mpv (video), imv (images), lf (files), Thunar (GUI files), btop (monitor)
- **Unified appearance** — GTK and Qt use same dark theme, font, and icons via qt5ct/qt6ct
- **Workspaces in Roman numerals** (I, II, III... X)
- **Random Stoic quote** when opening the terminal
- **Quotes Sync** — fetches Stoic quotes from external APIs with playlist rotation (each app gets a different quote)
- **OSD** — visual indicators for volume, brightness, CapsLock, and NumLock with 1% increments
- **Clipboard Manager** — history with pinned favorites via rofi
- **Stoatools** — utility tools (locksmith, resize, paste, OCR, rename) with Thunar integration
- **Greek column prompt** (Ι) in bronze with git branch
- **stoa-fetch** — system fetch with Greek temple ASCII art
- **stoa-walls** — wallpaper generator with ImageMagick
- **Vim navigation** (hjkl) in Hyprland, i3, and lf
- **Full Neovim theme** with Treesitter support
- **Colored man pages** in the Stoic palette
- **Screenshot** — grim+slurp+satty (Wayland) / maim (Xorg)
- **XDG MIME** configured — Brave for web, zathura for PDF, mpv for video, imv for images

## Design Philosophy

- **Simplicity** — Nothing superfluous, every element has a purpose
- **Harmony** — Natural colors that don't strain the eyes
- **Order** — Clean and well-documented configuration
- **Virtue** — Functional before beautiful

> *"Order is the first law of heaven."* — Marcus Aurelius

## License

GPL-3.0
