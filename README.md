# StoaLinux

Stoic dotfiles for Arch Linux. A minimalist customization inspired by Stoic philosophy, with colors of Roman marble, bronze, parchment, and stone.

**Hyprland (Wayland)** as primary compositor, **i3 (Xorg)** as fallback. Minimalist apps, Brave Browser, unified GTK/Qt appearance, custom Stoa theme across all apps.

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
| **Qalculate** | — | Scientific calculator (floating window) |
| **Enpass** | (AUR package) | Password manager |
| GTK 3.0 | `gtk-3.0/settings.ini`, `gtk-3.0/stoa-gtk.css` | Custom Stoa GTK3 theme |
| GTK 4.0 | `gtk-4.0/settings.ini`, `gtk-4.0/stoa-gtk.css` | Custom Stoa GTK4/libadwaita theme |
| Qt5/Qt6 | `qt5ct/`, `qt6ct/` | Qt standardized with GTK (Fusion dark) |
| Environment | `environment/stoa-env.sh` | Toolkit variables + default apps |
| Neofetch | `neofetch/config.conf` | Fetch with Stoic names |
| Zsh | `zsh/.zshrc` | Shell with quotes and Ι prompt |
| Bash | `zsh/.bashrc` | Bash alternative |
| Stoa Config | `stoa.conf` | Stoa settings (keybinds, etc.) |
| Colors | `colors.sh` | Central palette reference |

### Leisure

| Component | File | Description |
|-----------|------|-------------|
| **Steam** | `steam/stoa-steam.css` | Gaming with Proton — custom Stoa CSS overlay |
| **Calibre** | `calibre/stoa-calibre.py` | eBook library — Stoa dark theme with EB Garamond |
| **YACReader** | `yacreader/stoa-yacreader.qss` | Comic reader — full Stoa Qt stylesheet |

### Security

| Component | Description |
|-----------|-------------|
| **howdy** | Face recognition (Windows Hello-style) for lock screen and sudo |
| **Hyprlock** | Wayland lock screen with Stoa theme |
| **i3lock-color** | Xorg lock screen (fallback) |

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
| `stoa-settings` | All-in-one settings panel via rofi (Super+I) |
| `stoa-store` | Full package manager via rofi (Super+A) — search, install, remove, update |
| `stoa-face` | Face recognition setup and management (howdy) |

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

## Stoa Theme

StoaLinux applies a consistent Stoic visual identity across the entire system:

- **GTK 3/4** — Custom `stoa-gtk.css` with dark background, bronze accents, EB Garamond font
- **Qt 5/6** — Fusion dark theme matching GTK via qt5ct/qt6ct
- **Steam** — Chromium CSS overlay (`libraryroot.custom.css`) with Stoa palette
- **Calibre** — Dark reader theme with EB Garamond 18pt, bronze links, stone blockquotes
- **YACReader** — Full Qt stylesheet: menus, toolbars, scrollbars, comic view, all in Stoa colors
- **Icons** — Colloid-dark icon theme
- **Cursors** — Colloid cursors
- **Font** — EB Garamond (serif, system-wide), JetBrains Mono (monospace)

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
sudo pacman -S thunar thunar-volman thunar-archive-plugin catfish qalculate-gtk calibre

# Gaming (requires multilib enabled)
sudo pacman -S steam lib32-vulkan-icd-loader vulkan-icd-loader lib32-mesa

# Toolkit unification (GTK/Qt)
sudo pacman -S qt5ct qt6ct imagemagick

# Audio, fonts, extras
sudo pacman -S pipewire pipewire-pulse wireplumber brightnessctl jq curl
sudo pacman -S ttf-jetbrains-mono ttf-font-awesome
sudo pacman -S zsh git base-devel

# Lock screen
sudo pacman -S hyprlock i3lock-color

# Clipboard
sudo pacman -S wl-clipboard cliphist

# Stoatools (OCR, paste, resize, rename, locksmith)
sudo pacman -S tesseract tesseract-data-eng tesseract-data-por lsof wtype

# Developer tools
sudo pacman -S github-cli

# AUR: Widgets, Browser, Notes, Screenshot editor, Icons, Fonts, Security, Comics
yay -S eww-wayland brave-bin obsidian satty enpass-bin otf-eb-garamond \
       colloid-icon-theme-git colloid-cursors-git howdy yacreader
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
| `Super+C` | Calculator (Qalculate) |
| `Super+E` | Files (lf) |
| `Super+Shift+E` | Files (Thunar) |
| `Super+N` | Monitor (btop) |
| `Super+D` | Launcher (Rofi) |
| `Super+O` | Notes (Obsidian) |
| `Super+M` | Memento Mori (eww widget) |
| `Super+I` | Settings panel (rofi) |
| `Super+A` | App Store / Package manager (rofi) |
| `Super+V` | Clipboard (history) |
| `Super+Shift+V` | Clipboard (pin/unpin) |
| `Super+Shift+T` | OCR — extract text from screen |
| `Super+Shift+P` | Advanced Paste (formats) |
| `Super+/` | Bar keybinds (toggle) |
| `Super+Escape` | Lock screen |
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
- **Stoa GTK theme** — custom CSS for GTK3/GTK4/libadwaita with Stoic palette and EB Garamond
- **Brave Browser** as default browser (privacy + native Wayland)
- **Obsidian** as notes and second brain app (Markdown)
- **Memento Mori** — eww widget with days/weeks/years lived, year progress, and Stoic quote
- **Stoic apps**: zathura (PDF), mpv (video), imv (images), lf (files), Thunar (GUI files), btop (monitor)
- **Steam** with Proton for Windows games — custom Stoa CSS overlay, Vulkan drivers, multilib auto-enabled
- **Calibre** for eBooks — dark reading theme with EB Garamond serif font
- **YACReader** for comics — full Qt stylesheet in Stoa colors (CBR/CBZ/CB7)
- **stoa-settings** — all-in-one settings panel: wallpaper, theme, GPU, face recognition, lock screen
- **stoa-store** — package manager GUI via rofi: search, install, remove, update (pacman + AUR)
- **Face recognition (howdy)** — Windows Hello-style login for lock screen and sudo
- **Lock screen** — Hyprlock (Wayland) + i3lock-color (Xorg) with Stoa theme
- **Calculator** — Qalculate-gtk as floating window (Super+C)
- **Unified appearance** — GTK and Qt use same dark theme, EB Garamond font, Colloid icons and cursors
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
- **XDG MIME** configured — Brave for web, zathura for PDF, mpv for video, imv for images, Calibre for ebooks, YACReader for comics

## MIME Types

| Type | Application |
|------|-------------|
| Web (HTTP/HTTPS) | Brave Browser |
| PDF | Zathura |
| Images (PNG/JPG/GIF/WebP) | imv |
| Video (MP4/MKV/WebM) | mpv |
| Audio (MP3/FLAC/OGG) | mpv |
| eBooks (EPUB/MOBI/FB2) | Calibre |
| Comics (CBZ/CBR/CB7) | YACReader |
| Markdown | Obsidian |
| Directories | Thunar |

## Design Philosophy

- **Simplicity** — Nothing superfluous, every element has a purpose
- **Harmony** — Natural colors that don't strain the eyes
- **Order** — Clean and well-documented configuration
- **Virtue** — Functional before beautiful

> *"Order is the first law of heaven."* — Marcus Aurelius

## License

GPL-3.0
