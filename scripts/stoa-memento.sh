#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Memento Mori Toggle                           ║
# ║  "Remember that you will die." — Stoic tradition             ║
# ╚══════════════════════════════════════════════════════════════╝

WIDGET="memento"

WIDGET="memento"

if eww close "$WIDGET" 2>/dev/null; then
    exit 0
else
    eww open "$WIDGET" 2>/dev/null
    exit 0
fi