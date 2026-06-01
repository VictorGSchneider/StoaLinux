#!/bin/bash
# Toggle Noctalia (quickshell): kill if running, start if not.
if pgrep -x quickshell > /dev/null; then
    killall quickshell
else
    exec ~/.local/bin/stoa-bar
fi
