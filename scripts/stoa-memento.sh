#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Memento Mori Toggle                           ║
# ║  "Remember that you will die." — Stoic tradition             ║
# ╚══════════════════════════════════════════════════════════════╝

WIDGET="memento"

if eww active-windows | grep -q "$WIDGET"; then
    eww close "$WIDGET"
else
    eww open "$WIDGET"
fi
