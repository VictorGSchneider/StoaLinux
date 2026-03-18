# StoaLinux

> *"The happiness of your life depends upon the quality of your thoughts."* — Marcus Aurelius

An Arch Linux setup inspired by Stoic philosophy. Every detail — from the color palette to the terminal prompt — is designed to foster focus, discipline, and clarity of mind.

## Philosophy

Stoicism teaches that we don't control what happens, but we control how we respond. StoaLinux brings that principle to the desktop: a system that doesn't distract, doesn't over-decorate, doesn't get in your way. It just works.

The palette comes from the ancient world — marble, bronze, parchment, stone, terracotta — colors that evoke temples, statues, and manuscripts. The typography uses EB Garamond, a classical serif that reinforces this identity. Every terminal opens with a different Stoic quote. The Memento Mori widget reminds you that time is finite.

This isn't minimalism for aesthetics. It's minimalism by principle: **only what serves, stays**.

## What it is

- **Arch Linux** with automated installation (from live ISO or existing Arch)
- **Hyprland** (Wayland) as the main compositor, **i3** as Xorg fallback
- Unified dark theme across GTK, Qt, Steam, Calibre, YACReader, and everything else
- `stoa-*` scripts for wallpapers, settings, OCR, clipboard, GPU, and more
- Memento Mori widget (eww) built into the desktop

## Palette

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
  <tr><td><code>Super+A</code></td><td>App store</td><td><code>Super+1-0</code></td><td>Workspaces I–X</td></tr>
  <tr><td><code>Super+V</code></td><td>Clipboard history</td><td><code>Print / Super+Print</code></td><td>Screenshot</td></tr>
</table>

## Scripts & Stoatools

<table>
  <tr><th>Script</th><th>What it does</th><th>Stoatool</th><th>What it does</th></tr>
  <tr><td><code>stoa-settings</code></td><td>Settings panel</td><td><code>stoa-ocr</code></td><td>Extract text from screen</td></tr>
  <tr><td><code>stoa-store</code></td><td>Package manager</td><td><code>stoa-paste</code></td><td>Paste as UPPER/lower/etc</td></tr>
  <tr><td><code>stoa-fetch</code></td><td>System fetch</td><td><code>stoa-resize</code></td><td>Batch resize images</td></tr>
  <tr><td><code>stoa-walls</code></td><td>Wallpaper generator</td><td><code>stoa-rename</code></td><td>Regex rename + preview</td></tr>
  <tr><td><code>stoa-memento</code></td><td>Memento Mori widget</td><td><code>stoa-locksmith</code></td><td>See who locks a file</td></tr>
  <tr><td><code>stoa-clipboard</code></td><td>Clipboard + pins</td><td></td><td></td></tr>
  <tr><td><code>stoa-osd</code></td><td>Volume/brightness OSD</td><td></td><td></td></tr>
  <tr><td><code>stoa-quotes-sync</code></td><td>Fetch quotes online</td><td></td><td></td></tr>
  <tr><td><code>stoa-face</code></td><td>Face unlock (howdy)</td><td></td><td></td></tr>
  <tr><td><code>stoa-gpu-setup</code></td><td>GPU + CPU drivers</td><td></td><td></td></tr>
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

## License

GPL-3.0
