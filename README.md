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
- **Noctalia Shell** (QML on Quickshell) as the bar + quick-settings + notifications, themed via the bundled **Stoa color scheme**; **waybar** stays as an optional fallback via `STOA_BAR` in `stoa.conf`
- **25-panel settings app** via Rofi — display, audio, network, VPN, firewall, Bluetooth, disks, system health, and more
- **10 color presets** (Nord, Dracula, Gruvbox, Catppuccin...) + custom color editor applied system-wide
- **Unified dark theme** across GTK, Qt, Steam, Calibre, YACReader, OnlyOffice, Betterbird, VS Code, Neovim
- **Capture toolbar** (eww) — screenshot + recording with mode selection, toggle, and delay
- **System resilience** — pacman pre-transaction snapshots, hyprctl version adapter, health check on boot
- **Memento Mori widget** (eww), **Stoic quotes**, and a **living marble screensaver**
- **DFM** (Dotfile Manager) — GTK4 GUI to edit dotfiles in-place with smart widgets, backups, and GitHub sync
- **Text prediction popup** (eww) — system-wide word suggestions + emoji as you type, like Windows text suggestions
- **stoa-\* scripts** for wallpapers, clipboard, OCR, paste, resize, firewall, WinApps, and more

## Palette

The default palette is inspired by the ancient world — marble, bronze, parchment, stone. It can be changed entirely via `Super+S → Theme → Color Palette`, with **10 built-in presets** and a **custom color editor**.

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

Shell — zsh is the Stoa default login shell; bash is kept as a fallback. The
setup scripts (`arch-install.sh` / `post-install.sh`) seed both rc files and
`chsh` into zsh automatically. On an existing system where the setup scripts
weren't run, wire it up manually:
```bash
echo 'source ~/StoaLinux/shell/.zshrc'  >> ~/.zshrc
echo 'source ~/StoaLinux/shell/.bashrc' >> ~/.bashrc
chsh -s /bin/zsh   # switch to /bin/bash anytime to fall back
```

> `install.sh` deploys configs and `stoa-*` binaries as **symlinks** into the
> repo, so a `git pull` propagates updates live — no need to re-run the
> installer after every change. Keep the clone at a stable path
> (e.g. `~/StoaLinux`); if you move it, run `install.sh` again to refresh
> the link targets. Two files are deliberately copied instead of linked
> (`stoa.conf` and OnlyOffice `settings.json`) because the apps write to
> them and a symlink would push your edits back into the repo.

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

> **Hyprland config is Lua.** Since Hyprland 0.55 the compositor reads
> `~/.config/hypr/hyprland.lua` and hyprlang (`hyprland.conf`) is deprecated
> upstream. Stoa ships `config/hypr/hyprland.lua` — binds are `hl.bind()`,
> settings go through `hl.config()`, window rules are `hl.window_rule()`
> tables, and autostart hangs off `hl.on("hyprland.start", ...)`. **Hyprland
> 0.55 or newer is required**; `stoa-doctor` warns if the installed version
> is older. `install.sh` removes the old `hyprland.conf` symlink on upgrade.
> See the [Hyprland Lua docs](https://wiki.hypr.land/Configuring/Start/).

## Settings Panel

Everything is configured through `stoa-settings` (`Super+S`) — no external settings app needed.

<table>
  <tr><th>Panel</th><th>Features</th></tr>
  <tr><td><b>Display</b></td><td>Brightness, resolution, scale, rotation, multi-monitor (extend/mirror)</td></tr>
  <tr><td><b>Audio</b></td><td>Volume, output/input devices (PipeWire)</td></tr>
  <tr><td><b>Equalizer</b></td><td>8 built-in EQ presets + user presets via EasyEffects</td></tr>
  <tr><td><b>Night Light</b></td><td>Blue light filter (2500K–6500K), schedule (manual/sunset/custom)</td></tr>
  <tr><td><b>Keyboard</b></td><td>Layout (12 presets + custom), repeat rate, Caps Lock remap, NumLock, RGB lighting (color, mode, brightness via OpenRGB)</td></tr>
  <tr><td><b>Mouse & Touchpad</b></td><td>Sensitivity, accel, scroll, tap-to-click, 12 configurable gestures, DPI (100–25600), polling rate, DPI profiles</td></tr>
  <tr><td><b>Network</b></td><td>Wi-Fi, saved networks, network info (IP/DNS/gateway/signal)</td></tr>
  <tr><td><b>VPN</b></td><td>ProtonVPN: connect by country, P2P, Secure Core, kill switch</td></tr>
  <tr><td><b>Firewall</b></td><td>nftables: port list, allow/block, service toggle</td></tr>
  <tr><td><b>Bluetooth</b></td><td>Scan, connect, saved devices, forget</td></tr>
  <tr><td><b>Hardware</b></td><td>CPU, GPU, RAM, disks, battery, USB, PCI, sensors, cameras, input</td></tr>
  <tr><td><b>Disks & Storage</b></td><td>Overview, usage analyzer (drill-down), mount/unmount, SMART, benchmark, format, fsck, fstab, cleanup</td></tr>
  <tr><td><b>Printers</b></td><td>CUPS: add/remove printers, print queue, scanners (SANE)</td></tr>
  <tr><td><b>Cloud Drive</b></td><td>Google Drive, OneDrive, Dropbox, S3 via rclone</td></tr>
  <tr><td><b>Power Management</b></td><td>Power profiles, screen off timeout, auto suspend, battery info, fan & performance (NitroSense-like)</td></tr>
  <tr><td><b>Fan & Performance</b></td><td>Fan mode (auto/turbo/silent), fan speed (manual PWM), performance profiles (Eco→Turbo), GPU mode, KB backlight timeout, boot sound, LCD override. Supports: Div Acer Manager Max, acer-predator kernel module, NBFC, generic hwmon</td></tr>
  <tr><td><b>Date & Time</b></td><td>Timezone, NTP, manual time, 12/24h, language & locale</td></tr>
  <tr><td><b>Accessibility</b></td><td>Cursor size, text scale, animations, gaps, opacity, border width</td></tr>
  <tr><td><b>Screensaver</b></td><td>Living marble animation (plasma noise in Stoa palette), idle timeout</td></tr>
  <tr><td><b>Wallpaper</b></td><td>Browse, generate, set custom</td></tr>
  <tr><td><b>Theme</b></td><td>Color palette (10 presets + custom), GTK, icons, cursors, font size</td></tr>
  <tr><td><b>Lock Screen</b></td><td>Lock now, face recognition setup</td></tr>
  <tr><td><b>System Health</b></td><td>Doctor report, services status, failed units, thermals, journal, updates, package snapshots (diff), security audit, config integrity</td></tr>
  <tr><td><b>Maintenance</b></td><td>Backup configs, restore (interactive/bulk), full system cleanup (10-step), dry-run preview, schedule cleanup at boot</td></tr>
</table>

## Scripts & Stoatools

<table>
  <tr><th>Script</th><th>What it does</th><th>Stoatool</th><th>What it does</th></tr>
  <tr><td><code>stoa-settings</code></td><td>Settings panel (25 panels)</td><td><code>stoa-ocr</code></td><td>Extract text from screen</td></tr>
  <tr><td><code>stoa-store</code></td><td>Package manager</td><td><code>stoa-paste</code></td><td>Paste as UPPER/lower/etc</td></tr>
  <tr><td><code>stoa-fetch</code></td><td>System fetch</td><td><code>stoa-resize</code></td><td>Batch resize images</td></tr>
  <tr><td><code>stoa-walls</code></td><td>Wallpaper generator</td><td><code>stoa-rename</code></td><td>Regex rename + preview</td></tr>
  <tr><td><code>stoa-memento</code></td><td>Memento Mori widget</td><td><code>stoa-locksmith</code></td><td>See who locks a file</td></tr>
  <tr><td><code>stoa-doctor</code></td><td>System health check</td><td><code>stoa-predict</code></td><td>Text prediction + emoji suggestions</td></tr>
  <tr><td><code>stoa-capture</code></td><td>Screenshot + recording (eww)</td><td></td><td></td></tr>
  <tr><td><code>stoa-screensaver</code></td><td>Living marble screensaver</td><td></td><td></td></tr>
  <tr><td><code>stoa-clipboard</code></td><td>Clipboard + pins</td><td></td><td></td></tr>
  <tr><td><code>stoa-drive</code></td><td>Cloud drive (rclone)</td><td></td><td></td></tr>
  <tr><td><code>stoa-firewall</code></td><td>nftables firewall</td><td></td><td></td></tr>
  <tr><td><code>stoa-winapps</code></td><td>Windows apps (KVM/RDP)</td><td></td><td></td></tr>
  <tr><td><code>stoa-osd</code></td><td>Volume/brightness OSD</td><td></td><td></td></tr>
  <tr><td><code>stoa-quotes-sync</code></td><td>Fetch quotes online</td><td></td><td></td></tr>
  <tr><td><code>stoa-face</code></td><td>Face unlock (howdy)</td><td></td><td></td></tr>
  <tr><td><code>stoa-gpu-setup</code></td><td>GPU + CPU drivers</td><td></td><td></td></tr>
  <tr><td><code>stoa-maintain</code></td><td>Backup, restore, cleanup (BRCS)</td><td></td><td></td></tr>
  <tr><td><code>stoa-pkg-snapshot</code></td><td>Package snapshot (pacman hook)</td><td></td><td></td></tr>
  <tr><td><code>dfm</code></td><td>Dotfile Manager (GTK4 GUI)</td><td></td><td></td></tr>
</table>

## Apps

<table>
  <tr><th>App</th><th>Purpose</th><th>App</th><th>Purpose</th></tr>
  <tr><td>Brave</td><td>Browser</td><td>btop</td><td>Monitor</td></tr>
  <tr><td>Obsidian</td><td>Notes</td><td>Qalculate</td><td>Calculator</td></tr>
  <tr><td>Kitty</td><td>Terminal</td><td>eww</td><td>Widgets</td></tr>
  <tr><td>VS Code</td><td>IDE</td><td>Neovim</td><td>Editor</td></tr>
  <tr><td>Zathura</td><td>PDF</td><td>Calibre</td><td>eBooks</td></tr>
  <tr><td>mpv</td><td>Video/audio</td><td>YACReader</td><td>Comics</td></tr>
  <tr><td>OnlyOffice</td><td>Office suite</td><td>Enpass</td><td>Passwords</td></tr>
  <tr><td>Betterbird</td><td>Email</td><td>howdy</td><td>Face unlock</td></tr>
  <tr><td>imv</td><td>Images</td><td>lf / Thunar</td><td>Files</td></tr>
  <tr><td>EasyEffects</td><td>Audio equalizer</td><td>gammastep</td><td>Night light</td></tr>
  <tr><td>QEMU/KVM</td><td>WinApps (VM)</td><td>FreeRDP</td><td>Remote desktop</td></tr>
  <tr><td>Steam</td><td>Gaming (Proton)</td><td>GnuPG</td><td>Encryption & signing</td></tr>
</table>

## Theme

The Stoa theme is applied consistently across:

- **GTK 3/4** — `stoa-gtk.css` with dark palette + EB Garamond
- **Qt 5/6** — Fusion dark via qt5ct/qt6ct
- **VS Code** — full color theme (syntax + UI + terminal ANSI)
- **Neovim** — `stoa.vim` colorscheme with treesitter support
- **Steam** — CSS overlay (`libraryroot.custom.css`)
- **OnlyOffice** — custom JSON theme (`stoa-onlyoffice.json`)
- **Betterbird** — userChrome/userContent CSS (`stoa-betterbird.css`)
- **Calibre** — dark reader with EB Garamond 18pt
- **YACReader** — full Qt stylesheet
- **Div Acer Manager Max** — Avalonia AXAML theme (bronze buttons, stone cards, marble text)
- **Icons** — Colloid-dark
- **Cursors** — Colloid
- **Font** — EB Garamond (serif) + JetBrains Mono (mono)

### Color Palette Manager

Change the entire color scheme from `Super+S → Theme → Color Palette`:

- **Apply Preset** — pick from 10 palettes and apply with one click
- **Edit Colors** — customize any of the 11 core colors individually via hex input
- **View Current Palette** — see the active colors at a glance
- **Reset to Stoic** — restore the default marble/bronze palette

Changes propagate automatically to: Noctalia Shell (via `~/.config/noctalia/colorschemes/Stoa/Stoa.json`), Rofi, Waybar, Kitty, eww, GTK 3/4, Hyprland, hyprlock, i3, and `colors.sh`. Hyprland and Kitty reload live; Noctalia repaints on the next color-scheme selection — other apps take effect on restart.

### Stoa Greeter

Boot straight into a hyprlock prompt themed exactly like `Super+Esc` — no
display manager required. Enable it with:

```bash
bash setup/enable-stoa-greeter.sh           # enable
bash setup/enable-stoa-greeter.sh --disable # undo
```

What it wires up:

- **systemd autologin** on `tty1` via drop-in (`/etc/systemd/system/getty@tty1.service.d/stoa-autologin.conf`)
- **`.zprofile` / `.bash_profile`** sourcing `shell/stoa-autostart-hyprland.sh` to `exec Hyprland` when the shell lands on `tty1`
- **`hl.exec_cmd("hyprlock")`** as the first `hyprland.start` autostart call in `hyprland.lua`, so the lock page renders before anything else
- **`grace = 0`** in `hyprlock.conf` (a non-zero grace would let any keypress in the first N seconds bypass the password — fine for a normal lock, fatal for a greeter)

`post-install.sh` offers to run it interactively at the end.

### Stoa Greetd (alternative — unlocks the keyring on login)

Same idea as the Stoa Greeter, but using `greetd` + `tuigreet` themed in
bronze on tty1. Because greetd opens a real PAM session,
`pam_gnome_keyring` runs and unlocks the GNOME keyring with the login
password — so Brave (and any other libsecret client) stops asking for
the keyring password the first time it opens.

```bash
bash setup/enable-stoa-greetd.sh           # enable
bash setup/enable-stoa-greetd.sh --disable # undo
```

What it wires up:

- **`/etc/greetd/config.toml`** — `tuigreet --time --remember --asterisks --cmd Hyprland` themed in the Stoa palette
- **`/etc/pam.d/greetd`** — `pam_gnome_keyring.so` in both `auth` and `session` so the keyring destrava sozinho on every login
- **`greetd.service`** enabled on boot
- **Stoa Greeter teardown** — autologin drop-in and `.zprofile` / `.bash_profile` hooks are removed automatically (the two flows are mutually exclusive)
- **`hl.exec_cmd("hyprlock")`** in `hyprland.lua` is commented out (greetd already authenticated; locking again would force a double password). `--disable` restores it.

Pick one or the other:

| | Stoa Greeter (hyprlock) | Stoa Greetd (tuigreet) |
|---|---|---|
| Visual | hyprlock graphical lockscreen | TUI in tty1, bronze prompt |
| PAM session | no (auth only) | yes |
| Keyring unlocks on login | no | yes |
| Boot weight | lighter (autologin + lock) | a touch heavier (greetd daemon) |

### System Resilience

- **Package snapshots** — pacman pre-transaction hook saves `pacman -Q` before every install/upgrade/remove (`~/.config/stoa/pkg-snapshots/`, last 20, auto-rotates). Compare snapshots with current state to see exactly what changed.
- **Hyprland version adapter** — `stoa-doctor` detects `hyprctl` output format on boot and all 25+ settings calls adapt automatically via `_hyprctl_get()`.
- **Health check** — `stoa-doctor` runs on login, verifies all binary dependencies and services, and notifies via Noctalia Shell (which owns `org.freedesktop.Notifications` — scripts call `notify-send`). Full log at `~/.config/stoa/doctor.log`.

### Vendored upstreams

Some `stoa-*` scripts are forks of standalone projects and live alongside a
read-only copy of their upstream under `scripts/vendor/`. Pull new upstream
commits with:

```bash
scripts/vendor/sync-upstream.sh brcs   # updates scripts/vendor/brcs/
```

The helper does a squashed `git subtree pull`, then prints a diffstat of
the Stoa fork against the refreshed upstream so you can see which hunks
are candidates to forward-port. Currently vendored:

- **BRCS.sh** ([upstream](https://github.com/VictorGSchneider/BRCS.sh)) →
  fork at `scripts/stoa-maintain.sh`
- **DFM** ([upstream](https://github.com/VictorGSchneider/DFM)) →
  directory-based fork at `scripts/stoa-dfm/`

See `scripts/vendor/README.md` for the full arrangement and the one-time
bootstrap command.

### [DFM — Dotfile Manager](https://github.com/VictorGSchneider/DFM)

A GTK4/libadwaita GUI for editing dotfiles in-place — no moving, no centralizing. Launch with `Super+G`, from the Noctalia launcher, or `dfm`.

- **Smart widgets** — auto-generated toggles, sliders, color pickers, and path selectors based on config file content
- **Versioned backups** — automatic snapshots before every edit, with rollback support
- **Syntax validation** — JSON, TOML, YAML, INI, shell, Xresources, plus cross-file conflict detection
- **GitHub sync** — push/pull dotfiles via `gh`, create repos, share as Gists
- **80+ known configs** — shells, window managers, terminals, status bars, editors, and more
- **Profile management** — switch between configuration sets and built-in templates

`install.sh` installs the in-tree fork (`scripts/stoa-dfm/`) as an editable
package — `pipx install --editable` when available, a user venv otherwise —
so a `git pull` on StoaLinux propagates live to the running `dfm` binary,
matching the symlink semantics used for every other stoa-\* script. The
XDG desktop entry (`data/dfm.desktop`) is symlinked into
`~/.local/share/applications/` so the Noctalia launcher and other app grids pick it up.
`stoa-doctor` flags a missing `dfm` binary on login.

### Text Prediction

System-wide word suggestions and emoji picker, similar to Windows text suggestions. Toggle with `Super+Shift+S`.

- **Word completion** — as you type, a floating popup shows up to 5 dictionary-based suggestions (prefix match via `/usr/share/dict/words`)
- **Emoji suggestions** — related emojis appear alongside word completions (120+ keyword mappings built-in, extensible via `~/.config/stoa/predict-emojis.json`)
- **Click to insert** — selecting a suggestion erases the typed prefix and inserts the full word or emoji via `wtype`
- **Modifier-aware** — ignores keystrokes with Ctrl/Alt/Super (shortcuts don't trigger suggestions)
- **eww popup** — non-focusable overlay at bottom-center, styled with the Stoa palette
- **Multi-keyboard** — auto-detects all keyboard devices via evdev

Requires the user to be in the `input` group (handled automatically by `post-install.sh`).

## License

GPL-3.0
