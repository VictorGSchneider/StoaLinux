# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Hyprland autostart on tty1                    ║
# ║  "What stands in the way becomes the way." — Marcus Aurelius║
# ║                                                              ║
# ║  Sourced from ~/.zprofile / ~/.bash_profile. Combined with   ║
# ║  systemd autologin on tty1 (see setup/enable-stoa-greeter.sh)║
# ║  this boots straight into Hyprland, where the first          ║
# ║  exec-once is hyprlock — so the lock page IS the login.      ║
# ╚══════════════════════════════════════════════════════════════╝

if [ -z "$WAYLAND_DISPLAY" ] && [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ] && command -v Hyprland >/dev/null 2>&1; then
    exec Hyprland
fi
