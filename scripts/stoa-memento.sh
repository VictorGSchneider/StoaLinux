#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Memento Mori Toggle                           ║
# ║  "Remember that you will die." — Stoic tradition             ║
# ╚══════════════════════════════════════════════════════════════╝

WIDGET="memento"

# `eww active-windows` is not a real subcommand; `eww windows` marks
# active windows with a leading `*`.
if eww windows 2>/dev/null | grep -Eq "^\*.*${WIDGET}$"; then
    eww close "$WIDGET"
else
    eww open "$WIDGET"
fi
