#!/bin/bash
# Toggle the Stoa shell: kill if running, start if not.
#
# Covers both engines — noctalia v5 (a plain `noctalia` process) and the
# legacy v4 pair (a `quickshell` process) — so the keybind keeps working
# whichever one stoa-bar picked.
if pgrep -x noctalia > /dev/null; then
    killall noctalia
elif pgrep -x quickshell > /dev/null; then
    killall quickshell
elif pgrep -x waybar > /dev/null; then
    killall waybar
else
    exec ~/.local/bin/stoa-bar
fi
