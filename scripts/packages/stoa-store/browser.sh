#!/bin/bash
# Stoa Store — installed-package browsing.
#
# This used to carry a Synaptic-style rofi browser (filter by installed/
# explicit/orphans/groups/repos, search, broken-deps report, per-package
# detail). All of that is now bauh's job — a standalone GUI package
# manager that already covers Pacman, AUR, Flatpak, Snap and AppImage in
# one place. See core.sh's _open_bauh and stoa-store.sh's main menu.

_installed() { _open_bauh; }
