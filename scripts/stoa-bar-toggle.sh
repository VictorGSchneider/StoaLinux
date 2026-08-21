#!/bin/bash
# Toggle the Stoa shell: kill if running, start if not.
if pgrep -x noctalia > /dev/null; then
    killall noctalia
else
    exec ~/.local/bin/stoa-bar
fi
