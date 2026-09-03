#!/bin/bash
# Stoa Store — Pacman + AUR search/install/removal.
#
# This used to carry a rofi-driven search/detail UI (results parsing,
# dependency trees, install-with-preview, complete-removal planning...).
# All of that is now bauh's job — a standalone GUI package manager that
# already covers Pacman, AUR, Flatpak, Snap and AppImage in one place.
# See core.sh's _open_bauh and stoa-store.sh's main menu.

_search_install() { _open_bauh; }
