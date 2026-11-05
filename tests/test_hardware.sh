#!/bin/bash
# Runs the unit tests for scripts/stoa-hardware.py — see
# tests/stoa_hardware_test.py. Uses a fake sysfs; needs no hardware or udisks2.
cd "$(dirname "$0")/.." || exit 1
exec python3 -I tests/stoa_hardware_test.py -q
