#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Memento Mori Toggle                           ║
# ║  "Lembra-te de que vais morrer." — tradição estoica          ║
# ╚══════════════════════════════════════════════════════════════╝

WIDGET="memento"

if eww active-windows | grep -q "$WIDGET"; then
    eww close "$WIDGET"
else
    eww open "$WIDGET"
fi
