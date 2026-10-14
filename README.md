<div align="center">

# StoaLinux

**A Stoic desktop for Arch Linux — Hyprland (Wayland) and a unified dark theme inspired by the ancient world.**

[![Arch Linux](https://img.shields.io/badge/Arch_Linux-1793D1?style=flat-square&logo=archlinux&logoColor=white)](https://archlinux.org)
[![Hyprland](https://img.shields.io/badge/Hyprland-58E1FF?style=flat-square&logo=wayland&logoColor=black)](https://hyprland.org)
[![License](https://img.shields.io/badge/License-GPL--3.0-c49a5c?style=flat-square)](LICENSE)

> *"The happiness of your life depends upon the quality of your thoughts."* — Marcus Aurelius

</div>

---

## Why

Most rices start from zero and pile things on until the desktop looks like the person who built it. StoaLinux started the other way: from a complete, working system, with everything not earning its place taken back out. That's the distinction the Stoics drew between the sculptor who adds clay and the one who removes marble — Michelangelo said the statue was already in the stone. A desktop built by subtraction carries fewer opinions than one built by accumulation, because every element that survived had to argue for itself first.

It's also a distinction the Stoics drew about a life. A cluttered desktop and a cluttered mind fail the same test: neither one asked, of each thing it kept, whether it served. **Minimalism here isn't an aesthetic — it's the dichotomy of control applied to a window manager.** You don't control what a distro ships by default. You do control what stays after you've looked at it honestly. Marble, bronze, parchment, stone: the palette isn't decoration either — it's what's left when you strip a color scheme down to what temples, statues, and manuscripts actually looked like, instead of what's trending on a theme repository this month.

The Memento Mori widget sitting on the desktop is the clearest expression of this. It's not a gimmick — it's *premeditatio malorum* rendered in eww: a quiet, constant reminder that the hours you're spending configuring a window manager are hours you don't get back, so configure it once, well, and then go do something that isn't configuring a window manager. The Stoic quote on every new shell serves the same purpose from a different angle — not decoration, a nudge, every single time you open a terminal, back toward why you're at the machine at all.

None of this makes StoaLinux a religious project. It's a tool built on the premise that a system which asks *why* before it asks *how* ends up smaller, calmer, and easier to actually live inside — and that a Stoic reading a good desktop the same way they'd read a good text: for its restraint, not its feature count.

## What it is

StoaLinux is a complete Arch Linux environment — automated installation, a unified dark theme across every app it touches, a settings panel built to make external configuration tools unnecessary, and a family of `stoa-*` scripts that exist because the alternative was five different tools each solving a fifth of the problem.

Hyprland (Wayland) is the compositor, full stop — there's no Xorg fallback to maintain, because a fallback path nobody uses is not a feature, it's an unexamined habit. Noctalia handles the bar, launcher, control centre, notifications, clipboard history, wallpapers, and lock screen, themed through the bundled Stoa palette. A 23-panel settings app covers the rest — display, audio, network, VPN, firewall, Bluetooth, disks, system health — so nothing on the system asks you to open three unrelated apps to change one thing.

**Highlights, briefly:**

- Automated Arch installation, from live ISO or an existing system
- Hyprland/Wayland only — one compositor, well maintained, instead of two maintained halfway
- Noctalia as the shell layer, themed via the Stoa palette, with 10 built-in presets and a custom editor
- A 23-panel settings app that replaces the usual pile of separate config tools
- One dark theme, carried consistently into GTK, Qt, VS Code, Neovim, Steam, Calibre, and more
- Pacman pre-transaction snapshots, a boot-time health check, and a Hyprland version adapter — resilience that doesn't wait for you to notice something broke
- A DFM (Dotfile Manager) GUI for editing configs in place, with backups and rollback
- A living marble screensaver, a Memento Mori widget, and Stoic quotes on every shell — the philosophy isn't bolted onto the system, it's rendered by it

## Palette

Marble, bronze, parchment, stone — colors chosen because they're what survives from the ancient world, not because they photograph well. Changeable entirely via `Super+S → Theme → Color Palette`, with 10 presets and a custom editor if the default doesn't suit you — the point was never that you keep it, only that you consider it first.

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

**Presets:** Stoic (default), Nord, Dracula, Gruvbox, Catppuccin Mocha, Tokyo Night, Solarized Dark, Rose Pine, GitHub Dark, Base16 Default

## Install

A system you didn't install yourself is a system you don't understand yet. These commands get you there; what you do with it afterward is the part that was always the point.

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

zsh is the default login shell; bash stays as a fallback. The setup scripts wire up both automatically. On a system where they weren't run:
```bash
echo 'source ~/StoaLinux/shell/.zshrc'  >> ~/.zshrc
echo 'source ~/StoaLinux/shell/.bashrc' >> ~/.bashrc
chsh -s /bin/zsh   # switch to /bin/bash anytime to fall back
```

`install.sh` deploys configs and `stoa-*` binaries as **symlinks**, so `git pull` propagates updates live — no re-installing after every change. Keep the clone at a stable path (e.g. `~/StoaLinux`). `stoa.conf` and the OnlyOffice `settings.json` are copied instead of linked, because those apps write back into their own config and a symlink would push that back into the repo.

## Keybinds

<table>
  <tr><th>Key</th><th>Action</th><th>Key</th><th>Action</th></tr>
  <tr><td><code>Super+Return</code></td><td>Terminal (Kitty)</td><td><code>Super+Shift+V</code></td><td>Clipboard pin</td></tr>
  <tr><td><code>Super+B</code></td><td>Browser (Brave)</td><td><code>Super+Shift+T</code></td><td>OCR (screen text)</td></tr>
  <tr><td><code>Super+C</code></td><td>Calculator (Qalculate)</td><td><code>Super+Shift+P</code></td><td>Advanced paste</td></tr>
  <tr><td><code>Super+Space</code></td><td>Launcher (Noctalia)</td><td><code>Super+/</code></td><td>Keybinds bar</td></tr>
  <tr><td><code>Super+E</code></td><td>Files (Thunar)</td><td><code>Super+Escape</code></td><td>Lock screen</td></tr>
  <tr><td><code>Super+Shift+E</code></td><td>Files (lf)</td><td><code>Super+Q</code></td><td>Close</td></tr>
  <tr><td><code>Super+N</code></td><td>Monitor (btop)</td><td><code>Super+F</code></td><td>Fullscreen</td></tr>
  <tr><td><code>Super+O</code></td><td>Notes (Obsidian)</td><td><code>Super+R</code></td><td>Resize (HJKL)</td></tr>
  <tr><td><code>Super+S</code></td><td>Settings panel</td><td><code>Super+HJKL</code></td><td>Navigate</td></tr>
  <tr><td><code>Super+W</code></td><td>WinApps</td><td><code>Super+Shift+HJKL</code></td><td>Move window</td></tr>
  <tr><td><code>Super+A</code></td><td>App store</td><td><code>Super+G</code></td><td>Dotfile Manager (DFM)</td></tr>
  <tr><td><code>Super+V</code></td><td>Clipboard history</td><td><code>Super+1-0</code></td><td>Workspaces I–X</td></tr>
  <tr><td><code>Super+Shift+S</code></td><td>Text prediction</td><td><code>Print</code></td><td>Capture (screenshot/record)</td></tr>
</table>

> Hyprland config is Lua (0.55+ required). Stoa ships `config/hypr/hyprland.lua`; `stoa-doctor` will tell you if your Hyprland predates it.

## Settings Panel

Everything is configured through `stoa-settings` (`Super+S`) on the theory that a setting you have to hunt for across five apps is a setting you'll never actually change. 23 panels, one place:

<table>
  <tr><th>Panel</th><th>Covers</th></tr>
  <tr><td><b>Display / Audio / Equalizer / Night Light</b></td><td>Brightness, resolution, multi-monitor, volume, PipeWire devices, EQ presets, blue light schedule</td></tr>
  <tr><td><b>Keyboard / Mouse & Touchpad</b></td><td>Layouts, repeat rate, RGB (OpenRGB); sensitivity, gestures, DPI profiles</td></tr>
  <tr><td><b>Network / VPN / Firewall / Bluetooth</b></td><td>Wi-Fi, ProtonVPN, nftables rules, device pairing</td></tr>
  <tr><td><b>Hardware / Disks & Storage / Printers</b></td><td>Sensors and components; mount, SMART, benchmark, fsck; CUPS + SANE</td></tr>
  <tr><td><b>Cloud Drive</b></td><td>Google Drive, OneDrive, Dropbox, S3 via rclone</td></tr>
  <tr><td><b>Power / Fan & Performance</b></td><td>Power profiles, fan curves, performance modes, GPU mode — NitroSense-like, for the hardware that needs it</td></tr>
  <tr><td><b>Date & Time / Accessibility</b></td><td>Timezone, locale; cursor size, text scale, animation and opacity controls</td></tr>
  <tr><td><b>Screensaver / Wallpaper / Theme</b></td><td>Living marble animation; wallpaper browser/generator; palette, GTK, icons, cursors, font size</td></tr>
  <tr><td><b>System Health / Maintenance</b></td><td>Doctor report, failed units, security audit; backup, restore, 10-step cleanup, scheduled maintenance</td></tr>
</table>

## Scripts & Stoatools

A family of small, single-purpose `stoa-*` tools — each one exists because reaching for a general-purpose app to do one specific thing is its own kind of clutter.

<table>
  <tr><th>Script</th><th>What it does</th><th>Stoatool</th><th>What it does</th></tr>
  <tr><td><code>stoa-settings</code></td><td>Settings panel (23 panels)</td><td><code>stoa-ocr</code></td><td>Extract text from screen</td></tr>
  <tr><td><code>stoa-store</code></td><td>Package manager</td><td><code>stoa-paste</code></td><td>Paste as UPPER/lower/etc</td></tr>
  <tr><td><code>stoa-fetch</code></td><td>System fetch</td><td><code>stoa-resize</code></td><td>Batch resize images</td></tr>
  <tr><td><code>stoa-walls</code></td><td>Wallpaper generator</td><td><code>stoa-rename</code></td><td>Regex rename + preview</td></tr>
  <tr><td><code>stoa-memento</code></td><td>Memento Mori widget</td><td><code>stoa-locksmith</code></td><td>Find + end what's locking a file/folder</td></tr>
  <tr><td><code>stoa-doctor</code></td><td>System health check</td><td><code>stoa-predict</code></td><td>Text prediction + emoji suggestions</td></tr>
  <tr><td><code>stoa-capture</code></td><td>Screenshot + recording (eww)</td><td><code>stoa-archive</code></td><td>Compress selection / extract archives</td></tr>
  <tr><td><code>stoa-screensaver</code></td><td>Living marble screensaver</td><td></td><td></td></tr>
  <tr><td><code>stoa-clipboard</code></td><td>Clipboard + pins</td><td></td><td></td></tr>
  <tr><td><code>stoa-drive</code></td><td>Cloud drive (rclone)</td><td></td><td></td></tr>
  <tr><td><code>stoa-firewall</code></td><td>nftables firewall</td><td></td><td></td></tr>
  <tr><td><code>stoa-winapps</code></td><td>Windows apps (KVM/RDP)</td><td></td><td></td></tr>
  <tr><td><code>stoa-osd</code></td><td>Volume/brightness OSD</td><td></td><td></td></tr>
  <tr><td><code>stoa-quotes-sync</code></td><td>Fetch quotes online</td><td></td><td></td></tr>
  <tr><td><code>stoa-gpu-setup</code></td><td>GPU + CPU drivers</td><td></td><td></td></tr>
  <tr><td><code>stoa-maintain</code></td><td>Backup, restore, cleanup (BRCS)</td><td></td><td></td></tr>
  <tr><td><code>stoa-history</code></td><td>Prune shell history (secrets, noise, duplicates)</td><td></td><td></td></tr>
  <tr><td><code>stoa-pkg-snapshot</code></td><td>Package snapshot (pacman hook)</td><td></td><td></td></tr>
  <tr><td><code>dfm</code></td><td>Dotfile Manager (GTK4 GUI)</td><td></td><td></td></tr>
</table>

## Apps

The chosen ones — not the biggest name in each category, the one that does its job and gets out of the way.

<table>
  <tr><th>App</th><th>Purpose</th><th>App</th><th>Purpose</th></tr>
  <tr><td>Brave</td><td>Browser</td><td>btop</td><td>Monitor</td></tr>
  <tr><td>Obsidian</td><td>Notes</td><td>Qalculate</td><td>Calculator</td></tr>
  <tr><td>Kitty</td><td>Terminal</td><td>eww</td><td>Widgets</td></tr>
  <tr><td>VS Code</td><td>IDE</td><td>Neovim</td><td>Editor</td></tr>
  <tr><td>Zathura</td><td>PDF</td><td>Calibre</td><td>eBooks</td></tr>
  <tr><td>mpv</td><td>Video/audio</td><td>YACReader</td><td>Comics</td></tr>
  <tr><td>OnlyOffice</td><td>Office suite</td><td>Enpass</td><td>Passwords</td></tr>
  <tr><td>Betterbird</td><td>Email</td><td></td><td></td></tr>
  <tr><td>imv</td><td>Images</td><td>lf / Thunar</td><td>Files</td></tr>
  <tr><td>EasyEffects</td><td>Audio equalizer</td><td>gammastep</td><td>Night light</td></tr>
  <tr><td>QEMU/KVM</td><td>WinApps (VM)</td><td>FreeRDP</td><td>Remote desktop</td></tr>
  <tr><td>Steam</td><td>Gaming (Proton)</td><td>GnuPG</td><td>Encryption & signing</td></tr>
</table>

## Theme

A theme that stops at the terminal isn't a theme, it's a wallpaper. The Stoa palette is carried into every app it can reach — GTK 3/4, Qt (via qt5ct/qt6ct), VS Code, Neovim, Steam, OnlyOffice, Betterbird, Calibre, YACReader — because a system that looks like two different projects stitched together asks something of your attention that a coherent one doesn't. Icons are Colloid-dark, cursors Colloid, fonts EB Garamond for prose and JetBrains Mono for code.

The whole palette is swappable from `Super+S → Theme → Color Palette` — 10 presets or a custom editor over 11 core colors — and it propagates to Kitty, eww, GTK, Hyprland, and Noctalia automatically. Reset to Stoic restores the original, untouched.

### Under the hood

A few things exist to keep the system honest with itself, without asking you to think about them day to day:

- **Package snapshots** — every pacman transaction is snapshotted first (`~/.config/stoa/pkg-snapshots/`, last 20), so "what changed" is always answerable.
- **Health check** — `stoa-doctor` runs at login, checks dependencies and services, and notifies you only if something's actually wrong.
- **Stoa Greeter / Greetd** — two optional boot paths straight into a themed lock prompt, no display manager. `setup/enable-stoa-greeter.sh` (lighter, hyprlock-based) or `setup/enable-stoa-greetd.sh` (heavier, also unlocks your keyring on login). Mutually exclusive; `post-install.sh` offers the first one interactively.
- **`stoa-history`** — reads your shell history and prunes what stopped earning its place: leaked secrets, `/tmp` junk, `ls`/`cd` noise, stale duplicates. Nothing is written without `--apply`, and every pass is backed up first (`stoa-history restore` undoes it).
- **Text prediction** (`Super+Shift+S`) — a small floating popup for word and emoji suggestions as you type, because a keystroke you don't have to make is a keystroke you don't have to make.
- **DFM** (`Super+G`) — a GTK4 GUI for editing dotfiles in place, with versioned backups, validation, and GitHub sync, so "I broke my config" stops being a reason to dread editing it.
- **Checks** — `bash tests/run.sh` runs the same checks CI does: shell linting, config-format validation, and a set of StoaLinux-specific invariants (dead keybinds, pacman hooks pointing nowhere, that kind of thing).
- **Vendored upstreams** — a couple of `stoa-*` tools are forks of standalone projects, kept alongside a read-only copy of their upstream under `scripts/vendor/` so improvements can flow both ways. See `scripts/vendor/README.md`.

## License

GPL-3.0
