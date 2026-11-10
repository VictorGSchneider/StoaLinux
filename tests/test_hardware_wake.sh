#!/bin/bash
# Runs tests/stoa_hardware_wake_test.py: stoa-hardware must not run lspci
# (or nvidia-smi) while a GPU is runtime-suspended — both resume the card,
# which the health pill would then do every ten minutes. Fake sysfs and a
# recording run(); no hardware is touched.
cd "$(dirname "$0")/.." || exit 1
exec python3 -I -B tests/stoa_hardware_wake_test.py -q
