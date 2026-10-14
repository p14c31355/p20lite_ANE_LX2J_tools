#!/bin/bash
# Zero-delay CNXN attempt: wait for ANE fastboot (kernel) via libusb directly,
# claim, send the magic CNXN, read the piggyback.
set +m
cd ~/dev/p20-root
UV=/home/placeless/.hermes/bin/uv
timeout 100 "$UV" run --with pyusb --no-project python3 zerodelay_cnxn.py rings_night/v306_zerodelay.bin 2>&1 | tail -8
stat -c %s rings_night/v306_zerodelay.bin 2>/dev/null || true
