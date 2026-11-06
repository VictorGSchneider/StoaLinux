#!/bin/bash
# Toggle the Stoa shell: kill if running, start if not.
# ── --help ──
case "${1:-}" in
    -h|--help)
        cat <<'STOA_HELP'
stoa-bar-toggle — toggle the Stoa shell: stop Noctalia if it is running, start it if not.

USAGE
  stoa-bar-toggle

OPTIONS
  -h, --help    show this help

RESUMO RÁPIDO
  stoa-bar-toggle
  stoa-bar-toggle -h | --help
STOA_HELP
        exit 0
        ;;
esac

if pgrep -x noctalia > /dev/null; then
    killall noctalia
else
    exec ~/.local/bin/stoa-bar
fi
