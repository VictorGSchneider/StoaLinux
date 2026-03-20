<div align="center">

# StoaLinux

**A Stoic desktop for Arch Linux — Hyprland, i3, and a unified dark theme inspired by the ancient world.**

[![Arch Linux](https://img.shields.io/badge/Arch_Linux-1793D1?style=flat-square&logo=archlinux&logoColor=white)](https://archlinux.org)
[![Hyprland](https://img.shields.io/badge/Hyprland-58E1FF?style=flat-square&logo=wayland&logoColor=black)](https://hyprland.org)
[![License](https://img.shields.io/badge/License-GPL--3.0-c49a5c?style=flat-square)](LICENSE)

> *"The happiness of your life depends upon the quality of your thoughts."* — Marcus Aurelius

</div>

---

Marble, bronze, parchment, stone — colors from temples, statues, and manuscripts. EB Garamond as the serif. JetBrains Mono in the terminal. A Stoic quote every time you open a shell. A Memento Mori widget on the desktop reminding you that time is finite.

StoaLinux is a complete Arch Linux environment with automated installation, a unified dark theme across every app, a settings panel that replaces the need for any external configuration tool, and a collection of `stoa-*` scripts that handle everything from wallpapers to OCR to cloud drives.

This isn't minimalism for aesthetics. It's minimalism by principle: **only what serves, stays**.

### Highlights

- **Arch Linux** with automated installation (from live ISO or existing Arch)
- **Hyprland** (Wayland) as the main compositor, **i3** as Xorg fallback
- **20-panel settings app** via Rofi — display, audio, network, VPN, firewall, Bluetooth, themes, and more
- **10 color presets** (Nord, Dracula, Gruvbox, Catppuccin...) + custom color editor applied system-wide
- **Unified dark theme** across GTK, Qt, Steam, Calibre, YACReader, OnlyOffice, Betterbird
- **Memento Mori widget** (eww), **Stoic quotes**, and a **living marble screensaver**
- **DFM** (Dotfile Manager) — GTK4 GUI to edit dotfiles in-place with smart widgets, backups, and GitHub sync
- **stoa-\* scripts** for wallpapers, clipboard, OCR, paste, resize, firewall, WinApps, and more

## Palette

The default palette is inspired by the ancient world — marble, bronze, parchment, stone. It can be changed entirely via `Super+I → Theme → Color Palette`, with **10 built-in presets** and a **custom color editor**.

<table>
  <tr>
    <td><img src="https://img.shields.io/badge/Background__%23211e19-211e19?style=for-the-badge&labelColor=211e19&color=211e19" alt="#211e19"/></td>
    <td><img src="https://img.shields.io/badge/Marble__%23d4cfc4-d4cfc4?style=for-the-badge&labelColor=d4cfc4&color=d4cfc4" alt="#d4cfc4"/></td>
    <td><img src="https://img.shields.io/badge/Bronze__%23c49a5c-c49a5c?style=for-the-badge&labelColor=c49a5c&color=c49a5c" alt="#c49a5c"/></td>
  </tr>
  <tr>
    <td><img src="https://img.shields.io/badge/Gold__%23d4a84b-d4a84b?style=for-the-badge&labelColor=d4a84b&color=d4a84b" alt="#d4a84b"/></td>
    <td><img src="https://img.shields.io/badge/Parchment__%23c4b08a-c4b08a?style=for-the-badge&labelColor=c4b08a&color=c4b08a" alt="#c4b08a"/></td>
    <td><img src="https://img.shields.io/badge/Olive__%238a9a6c-8a9a6c?style=for-the-badge&labelColor=8a9a6c&color=8a9a6c" alt="#8a9a6c"/></td>
  </tr>
  <tr>
    <td><img src="https://img.shields.io/badge/Terracotta__%23b36b5a-b36b5a?style=for-the-badge&labelColor=b36b5a&color=b36b5a" alt="#b36b5a"/></td>
    <td><img src="https://img.shields.io/badge/Azure__%235a7a8a-5a7a8a?style=for-the-badge&labelColor=5a7a8a&color=5a7a8a" alt="#5a7a8a"/></td>
    <td><img src="https://img.shields.io/badge/Stone__%236e6a62-6e6a62?style=for-the-badge&labelColor=6e6a62&color=6e6a62" alt="#6e6a62"/></td>
  </tr>
</table>

**Available presets:** Stoic (default), Nord, Dracula, Gruvbox, Catppuccin Mocha, Tokyo Night, Solarized Dark, Rose Pine, GitHub Dark, Base16 Default

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

<table>
  <tr><th>Key</th><th>Action</th><th>Key</th><th>Action</th></tr>
  <tr><td><code>Super+Return</code></td><td>Terminal (Kitty)</td><td><code>Super+Shift+V</code></td><td>Clipboard pin</td></tr>
  <tr><td><code>Super+B</code></td><td>Browser (Brave)</td><td><code>Super+Shift+T</code></td><td>OCR (screen text)</td></tr>
  <tr><td><code>Super+C</code></td><td>Calculator (Qalculate)</td><td><code>Super+Shift+P</code></td><td>Advanced paste</td></tr>
  <tr><td><code>Super+D</code></td><td>Launcher (Rofi)</td><td><code>Super+/</code></td><td>Keybinds bar</td></tr>
  <tr><td><code>Super+E</code></td><td>Files (lf)</td><td><code>Super+Escape</code></td><td>Lock screen</td></tr>
  <tr><td><code>Super+Shift+E</code></td><td>Files (Thunar)</td><td><code>Super+Q</code></td><td>Close</td></tr>
  <tr><td><code>Super+N</code></td><td>Monitor (btop)</td><td><code>Super+F</code></td><td>Fullscreen</td></tr>
  <tr><td><code>Super+O</code></td><td>Notes (Obsidian)</td><td><code>Super+R</code></td><td>Resize (HJKL)</td></tr>
  <tr><td><code>Super+M</code></td><td>Memento Mori</td><td><code>Super+HJKL</code></td><td>Navigate</td></tr>
  <tr><td><code>Super+I</code></td><td>Settings panel</td><td><code>Super+Shift+HJKL</code></td><td>Move window</td></tr>
  <tr><td><code>Super+W</code></td><td>WinApps</td><td><code>Super+G</code></td><td>Dotfile Manager (DFM)</td></tr>
  <tr><td><code>Super+A</code></td><td>App store</td><td><code>Super+1-0</code></td><td>Workspaces I–X</td></tr>
  <tr><td><code>Super+V</code></td><td>Clipboard history</td><td><code>Print / Super+Print</code></td><td>Screenshot</td></tr>
</table>

## Settings Panel

Everything is configured through `stoa-settings` (`Super+I`) — no external settings app needed.

<table>
  <tr><th>Panel</th><th>Features</th></tr>
  <tr><td><b>Display</b></td><td>Brightness, resolution, scale, rotation, multi-monitor (extend/mirror)</td></tr>
  <tr><td><b>Audio</b></td><td>Volume, output/input devices (PipeWire)</td></tr>
  <tr><td><b>Equalizer</b></td><td>8 built-in EQ presets + user presets via EasyEffects</td></tr>
  <tr><td><b>Night Light</b></td><td>Blue light filter (2500K–6500K), schedule (manual/sunset/custom)</td></tr>
  <tr><td><b>Keyboard</b></td><td>Layout (12 presets + custom), repeat rate, Caps Lock remap, NumLock</td></tr>
  <tr><td><b>Mouse & Touchpad</b></td><td>Sensitivity, accel, scroll, tap-to-click, 12 configurable gestures</td></tr>
  <tr><td><b>Network</b></td><td>Wi-Fi, saved networks, network info (IP/DNS/gateway/signal)</td></tr>
  <tr><td><b>VPN</b></td><td>ProtonVPN: connect by country, P2P, Secure Core, kill switch</td></tr>
  <tr><td><b>Firewall</b></td><td>nftables: port list, allow/block, service toggle</td></tr>
  <tr><td><b>Bluetooth</b></td><td>Scan, connect, saved devices, forget</td></tr>
  <tr><td><b>Hardware</b></td><td>CPU, GPU, RAM, disks, battery, USB, PCI, sensors, cameras, input</td></tr>
  <tr><td><b>Printers</b></td><td>CUPS: add/remove printers, print queue, scanners (SANE)</td></tr>
  <tr><td><b>Power Management</b></td><td>Power profiles, screen off timeout, auto suspend, battery info</td></tr>
  <tr><td><b>Date & Time</b></td><td>Timezone, NTP, manual time, 12/24h, language & locale</td></tr>
  <tr><td><b>Accessibility</b></td><td>Cursor size, text scale, animations, gaps, opacity, border width</td></tr>
  <tr><td><b>Screensaver</b></td><td>Living marble animation (plasma noise in Stoa palette), idle timeout</td></tr>
  <tr><td><b>Wallpaper</b></td><td>Browse, generate, set custom</td></tr>
  <tr><td><b>Theme</b></td><td>Color palette (10 presets + custom), GTK, icons, cursors, font size</td></tr>
  <tr><td><b>Lock Screen</b></td><td>Lock now, face recognition setup</td></tr>
</table>

## Scripts & Stoatools

<table>
  <tr><th>Script</th><th>What it does</th><th>Stoatool</th><th>What it does</th></tr>
  <tr><td><code>stoa-settings</code></td><td>Settings panel (20 panels)</td><td><code>stoa-ocr</code></td><td>Extract text from screen</td></tr>
  <tr><td><code>stoa-store</code></td><td>Package manager</td><td><code>stoa-paste</code></td><td>Paste as UPPER/lower/etc</td></tr>
  <tr><td><code>stoa-fetch</code></td><td>System fetch</td><td><code>stoa-resize</code></td><td>Batch resize images</td></tr>
  <tr><td><code>stoa-walls</code></td><td>Wallpaper generator</td><td><code>stoa-rename</code></td><td>Regex rename + preview</td></tr>
  <tr><td><code>stoa-memento</code></td><td>Memento Mori widget</td><td><code>stoa-locksmith</code></td><td>See who locks a file</td></tr>
  <tr><td><code>stoa-screensaver</code></td><td>Living marble screensaver</td><td></td><td></td></tr>
  <tr><td><code>stoa-clipboard</code></td><td>Clipboard + pins</td><td></td><td></td></tr>
  <tr><td><code>stoa-drive</code></td><td>Cloud drive (rclone)</td><td></td><td></td></tr>
  <tr><td><code>stoa-firewall</code></td><td>nftables firewall</td><td></td><td></td></tr>
  <tr><td><code>stoa-winapps</code></td><td>Windows apps (KVM/RDP)</td><td></td><td></td></tr>
  <tr><td><code>stoa-osd</code></td><td>Volume/brightness OSD</td><td></td><td></td></tr>
  <tr><td><code>stoa-quotes-sync</code></td><td>Fetch quotes online</td><td></td><td></td></tr>
  <tr><td><code>stoa-face</code></td><td>Face unlock (howdy)</td><td></td><td></td></tr>
  <tr><td><code>stoa-gpu-setup</code></td><td>GPU + CPU drivers</td><td></td><td></td></tr>
  <tr><td><code>dfm</code></td><td>Dotfile Manager (GTK4 GUI)</td><td></td><td></td></tr>
</table>

## Apps

<table>
  <tr><th>App</th><th>Purpose</th><th>App</th><th>Purpose</th></tr>
  <tr><td>Brave</td><td>Browser</td><td>btop</td><td>Monitor</td></tr>
  <tr><td>Obsidian</td><td>Notes</td><td>Qalculate</td><td>Calculator</td></tr>
  <tr><td>Kitty</td><td>Terminal</td><td>eww</td><td>Memento Mori widget</td></tr>
  <tr><td>Neovim</td><td>Editor</td><td>Steam</td><td>Gaming (Proton)</td></tr>
  <tr><td>Zathura</td><td>PDF</td><td>Calibre</td><td>eBooks</td></tr>
  <tr><td>mpv</td><td>Video/audio</td><td>YACReader</td><td>Comics</td></tr>
  <tr><td>OnlyOffice</td><td>Office suite</td><td>Enpass</td><td>Passwords</td></tr>
  <tr><td>Betterbird</td><td>Email</td><td>howdy</td><td>Face unlock</td></tr>
  <tr><td>imv</td><td>Images</td><td>lf / Thunar</td><td>Files</td></tr>
  <tr><td>EasyEffects</td><td>Audio equalizer</td><td>gammastep</td><td>Night light</td></tr>
  <tr><td>QEMU/KVM</td><td>WinApps (VM)</td><td>FreeRDP</td><td>Remote desktop</td></tr>
</table>

## Theme

The Stoa theme is applied consistently across:

- **GTK 3/4** — `stoa-gtk.css` with dark palette + EB Garamond
- **Qt 5/6** — Fusion dark via qt5ct/qt6ct
- **Steam** — CSS overlay (`libraryroot.custom.css`)
- **OnlyOffice** — custom JSON theme (`stoa-onlyoffice.json`)
- **Betterbird** — userChrome/userContent CSS (`stoa-betterbird.css`)
- **Calibre** — dark reader with EB Garamond 18pt
- **YACReader** — full Qt stylesheet
- **Icons** — Colloid-dark
- **Cursors** — Colloid
- **Font** — EB Garamond (serif) + JetBrains Mono (mono)

### Color Palette Manager

Change the entire color scheme from `Super+I → Theme → Color Palette`:

- **Apply Preset** — pick from 10 palettes and apply with one click
- **Edit Colors** — customize any of the 11 core colors individually via hex input
- **View Current Palette** — see the active colors at a glance
- **Reset to Stoic** — restore the default marble/bronze palette

Changes propagate automatically to: Rofi, Waybar, Kitty, Dunst, eww, GTK 3/4, Hyprland, hyprlock, i3, and `colors.sh`. Hyprland, Kitty, and Dunst reload live — other apps take effect on restart.

### DFM — Dotfile Manager

A GTK4/libadwaita GUI for editing dotfiles in-place — no moving, no centralizing. Launch with `Super+G` or `dfm`.

- **Smart widgets** — auto-generated toggles, sliders, color pickers, and path selectors based on config file content
- **Versioned backups** — automatic snapshots before every edit, with rollback support
- **Syntax validation** — JSON, TOML, YAML, INI, shell, Xresources, plus cross-file conflict detection
- **GitHub sync** — push/pull dotfiles via `gh`, create repos, share as Gists
- **80+ known configs** — shells, window managers, terminals, status bars, editors, and more
- **Profile management** — switch between configuration sets and built-in templates

## License

GPL-3.0
