# scripts/

Every `stoa-*` command, grouped by what it does. `install.sh` links each one
into `~/.local/bin` under its short name (`scripts/wallpaper/stoa-walls.sh` →
`stoa-walls`), so nothing you type changes with the folder it lives in.

| Folder | What lives there |
|---|---|
| `desktop/` | Session and shell: `stoa-bar`, `stoa-bar-toggle`, `stoa-wm`, `stoa-display`, `stoa-osd`, `stoa-screensaver`, `stoa-keybinds-bar`, `stoa-keybinds-toggle`, and the `stoa-settings` panel |
| `wallpaper/` | Wallpapers and the memento widget: `stoa-walls` (+ `stoa-walls-ai.py`), `stoa-quotes-sync`, `stoa-memento-data` |
| `drive/` | Cloud drives (rclone): `stoa-drive`, `stoa-drive-status`, `-pin`, `-unpin`, `-emblems` |
| `health/` | Checks and status for the bar pills: `stoa-doctor`, `stoa-doctor-status`, `stoa-health`, `stoa-vitals-status`, `stoa-hardware.py` |
| `system/` | System administration: `stoa-maintain`, `stoa-gpu-setup`, `stoa-firewall`, `stoa-locksmith`, `stoa-snapshot`, `stoa-snapshots/` |
| `files/` | File actions (Thunar "Stoatools") and `stoa-dfm/`, the dotfile manager fork |
| `input/` | Paste, OCR and text prediction: `stoa-paste`, `stoa-ocr`, `stoa-predict` (+ `.py`, `stoa-predict-protocols/`) |
| `packages/` | Software: `stoa-store` (+ `stoa-store/`), `stoa-bauh.py`, `stoa-pkg-snapshot` |
| `tools/` | Everything else: `stoa-fetch`, `stoa-history.py`, `stoa-sync` |
| `lib/` | Shared shell libraries (`stoa-paths.sh`, `stoa-wm.sh`, `stoa-yad.sh`), sourced by the scripts above |
| `vendor/` | Upstream copies of the projects the Stoa forks track; see `vendor/README.md` |

## Adding a script

- Put it in the folder that matches what it does; a folder only makes sense
  if two or more scripts share it, so prefer an existing one.
- Find shared code relative to the script, not to the repo root. From
  `scripts/<folder>/stoa-x.sh`, the libraries are at `../lib` and the repo
  root is `../..` (resolve symlinks first: `readlink -f "${BASH_SOURCE[0]}"`).
- A script that needs a sibling (`stoa-walls` → `stoa-walls-ai.py`) keeps it
  in the same folder, so the lookup is just the script's own directory.
- Add the `_link` line to `install.sh`.
