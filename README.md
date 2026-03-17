# StoaLinux

Stoic dotfiles for Arch Linux — marble, bronze, parchment, stone.

**Hyprland** (Wayland) + **i3** (Xorg fallback). Dark theme everywhere.

> *"The happiness of your life depends upon the quality of your thoughts."* — Marcus Aurelius

## Palette

<p>
  <img src="https://img.shields.io/badge/Background__%23211e19-211e19?style=for-the-badge&labelColor=211e19&color=211e19" alt="#211e19"/>
  <img src="https://img.shields.io/badge/Marble__%23d4cfc4-d4cfc4?style=for-the-badge&labelColor=d4cfc4&color=d4cfc4" alt="#d4cfc4"/>
  <img src="https://img.shields.io/badge/Bronze__%23c49a5c-c49a5c?style=for-the-badge&labelColor=c49a5c&color=c49a5c" alt="#c49a5c"/>
  <img src="https://img.shields.io/badge/Gold__%23d4a84b-d4a84b?style=for-the-badge&labelColor=d4a84b&color=d4a84b" alt="#d4a84b"/>
  <img src="https://img.shields.io/badge/Parchment__%23c4b08a-c4b08a?style=for-the-badge&labelColor=c4b08a&color=c4b08a" alt="#c4b08a"/>
  <img src="https://img.shields.io/badge/Olive__%238a9a6c-8a9a6c?style=for-the-badge&labelColor=8a9a6c&color=8a9a6c" alt="#8a9a6c"/>
  <img src="https://img.shields.io/badge/Terracotta__%23b36b5a-b36b5a?style=for-the-badge&labelColor=b36b5a&color=b36b5a" alt="#b36b5a"/>
  <img src="https://img.shields.io/badge/Azure__%235a7a8a-5a7a8a?style=for-the-badge&labelColor=5a7a8a&color=5a7a8a" alt="#5a7a8a"/>
  <img src="https://img.shields.io/badge/Stone__%236e6a62-6e6a62?style=for-the-badge&labelColor=6e6a62&color=6e6a62" alt="#6e6a62"/>
</p>

## Structure

```
StoaLinux/
├── config/         ← app dotfiles (~/.config/)
│   ├── hypr/           hyprland.conf + hyprlock.conf
│   ├── waybar/         config + style.css
│   ├── i3/             config + i3status.conf
│   ├── alacritty/      alacritty.toml
│   ├── nvim/           init.vim + colors/stoa.vim
│   ├── rofi/           config.rasi
│   ├── dunst/          dunstrc
│   ├── eww/            eww.yuck + eww.scss (Memento Mori)
│   ├── picom/          picom.conf (Xorg)
│   ├── thunar/         uca.xml (Stoatools actions)
│   ├── zathura/        mpv/  imv/  lf/  btop/  neofetch/
│   └── ...
│
├── theme/          ← visual identity
│   ├── gtk-3.0/        settings.ini + stoa-gtk.css
│   ├── gtk-4.0/        settings.ini + stoa-gtk.css
│   ├── qt5ct/          qt5ct.conf
│   ├── qt6ct/          qt6ct.conf
│   ├── steam/          stoa-steam.css
│   ├── calibre/        stoa-calibre.py
│   ├── yacreader/      stoa-yacreader.qss
│   ├── pacman-hooks/   auto-reapply theme on updates
│   └── colors.sh       palette reference
│
├── shell/          ← shell configs
│   ├── .zshrc          zsh with Stoic quotes + Ι prompt
│   ├── .bashrc         bash alternative
│   └── stoa-env.sh     env vars (GTK/Qt/cursor/Steam)
│
├── scripts/        ← stoa-* commands
│
├── setup/          ← installation
│   ├── arch-install.sh     from live ISO
│   ├── archinstall/        archinstall config
│   └── post-install.sh     existing Arch
│
├── install.sh      ← dotfiles entry point
├── stoa.conf       ← user settings
└── README.md
```

## Install

**From live ISO:**
```bash
curl -LO https://raw.githubusercontent.com/VictorGSchneider/StoaLinux/main/setup/arch-install.sh
chmod +x arch-install.sh && ./arch-install.sh
```

**Existing Arch:**
```bash
git clone https://github.com/VictorGSchneider/StoaLinux.git
cd StoaLinux && chmod +x setup/post-install.sh && ./setup/post-install.sh
```

**Dotfiles only:**
```bash
git clone https://github.com/VictorGSchneider/StoaLinux.git
cd StoaLinux && chmod +x install.sh && ./install.sh
```

Shell (add manually):
```bash
echo 'source ~/StoaLinux/shell/.zshrc' >> ~/.zshrc   # or .bashrc
```

## Keybinds

| Key | Action |
|-----|--------|
| `Super+Return` | Terminal (Alacritty) |
| `Super+B` | Browser (Brave) |
| `Super+C` | Calculator (Qalculate) |
| `Super+D` | Launcher (Rofi) |
| `Super+E` | Files (lf) |
| `Super+Shift+E` | Files (Thunar) |
| `Super+N` | Monitor (btop) |
| `Super+O` | Notes (Obsidian) |
| `Super+M` | Memento Mori |
| `Super+I` | Settings panel |
| `Super+A` | App store |
| `Super+V` | Clipboard history |
| `Super+Shift+V` | Clipboard pin |
| `Super+Shift+T` | OCR (screen text) |
| `Super+Shift+P` | Advanced paste |
| `Super+/` | Keybinds bar |
| `Super+Escape` | Lock screen |
| `Super+Q` | Close |
| `Super+F` | Fullscreen |
| `Super+R` | Resize (HJKL) |
| `Super+HJKL` | Navigate |
| `Super+Shift+HJKL` | Move window |
| `Super+1-0` | Workspaces I–X |
| `Print` | Screenshot (full) |
| `Super+Print` | Screenshot (area) |

## Scripts

| Command | What it does |
|---------|-------------|
| `stoa-settings` | Settings panel — wallpaper, theme, GPU, face, lock |
| `stoa-store` | Package manager — search, install, remove, update |
| `stoa-fetch` | System fetch with temple ASCII |
| `stoa-walls` | Wallpaper generator |
| `stoa-memento` | Memento Mori widget |
| `stoa-clipboard` | Clipboard with pinned favorites |
| `stoa-osd` | Volume/brightness/caps OSD |
| `stoa-quotes-sync` | Fetch Stoic quotes online |
| `stoa-face` | Face recognition setup (howdy) |
| `stoa-gpu-setup` | GPU + CPU driver setup |

**Stoatools** (also Thunar right-click actions):

| Command | What it does |
|---------|-------------|
| `stoa-ocr` | Extract text from screen/image |
| `stoa-paste` | Paste as UPPER/lower/Title/snake/camel/JSON/Markdown |
| `stoa-resize` | Batch resize images |
| `stoa-rename` | Regex rename with preview |
| `stoa-locksmith` | See who's locking a file |

## Apps

| App | Purpose |
|-----|---------|
| Brave | Browser |
| Obsidian | Notes |
| Alacritty | Terminal |
| Neovim | Editor |
| Zathura | PDF |
| mpv | Video/audio |
| imv | Images |
| lf / Thunar | Files |
| btop | Monitor |
| Qalculate | Calculator |
| eww | Memento Mori widget |
| Steam | Gaming (Proton) |
| Calibre | eBooks |
| YACReader | Comics |
| Enpass | Passwords |
| howdy | Face unlock |

## Theme

The Stoa theme is applied consistently across:

- **GTK 3/4** — `stoa-gtk.css` with dark palette + EB Garamond
- **Qt 5/6** — Fusion dark via qt5ct/qt6ct
- **Steam** — CSS overlay (`libraryroot.custom.css`)
- **Calibre** — dark reader with EB Garamond 18pt
- **YACReader** — full Qt stylesheet
- **Icons** — Colloid-dark
- **Cursors** — Colloid
- **Font** — EB Garamond (serif) + JetBrains Mono (mono)

## License

GPL-3.0
