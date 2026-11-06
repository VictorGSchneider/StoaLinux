#!/usr/bin/env python3
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Bauh launcher (Python 3.12+ compat shim)        ║
# ╚══════════════════════════════════════════════════════════════╝
#
# bauh (AUR) still calls the stdlib pkgutil.find_loader() to detect its
# gem plugins (bauh/view/core/gems.py), but that function was removed in
# Python 3.12+ (deprecated since 3.4). On any Arch install with a current
# Python, bare `bauh` crashes on startup with:
#   AttributeError: module 'pkgutil' has no attribute 'find_loader'
# Upstream hasn't released a fix (last release: 0.10.7, Jan 2024); the
# known-good replacement is importlib.util.find_spec, which returns an
# equivalent loader object. We patch pkgutil before bauh imports run,
# so this is a no-op the day upstream (or Python) fixes it for real.
#
# install.sh symlinks this file to BOTH ~/.local/bin/stoa-bauh and
# ~/.local/bin/bauh — the latter so that typing plain `bauh` in a
# terminal also gets the patched launcher (~/.local/bin comes before
# /usr/bin in PATH; see shell/.zshrc, shell/.bashrc), not just Stoa
# Store's "Search & install" menu entry.
import pkgutil
import sys

if not hasattr(pkgutil, "find_loader"):
    import importlib.util

    def _find_loader(name):
        spec = importlib.util.find_spec(name)
        return spec.loader if spec else None

    pkgutil.find_loader = _find_loader

try:
    from bauh.app import main
except ImportError:
    print("stoa-bauh: bauh is not installed. Install it via: yay -S bauh", file=sys.stderr)
    sys.exit(1)

sys.exit(main())
