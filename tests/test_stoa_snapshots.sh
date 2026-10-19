#!/bin/bash
# Runs the unit tests for the snapshot browser's logic
# (scripts/stoa-snapshots/stoa_snapshots/core.py) — see
# tests/stoa_snapshots_test.py. No GTK needed.
cd "$(dirname "$0")/.." || exit 1
exec python3 -I tests/stoa_snapshots_test.py -q
