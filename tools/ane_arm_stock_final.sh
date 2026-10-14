#!/bin/bash
# Final: restore the stock kernel so the phone boots normal Android. One combo
# into the loader's fastboot, flash, reboot - then the handset is a phone
# again and the USB can go.
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
STOCK=firmware/kernel_stock.bin
say(){ echo "[$(date +%H:%M:%S)] $*"; }
say "waiting for fastboot (combo) to restore the STOCK kernel"
while ! timeout 10 fastboot devices 2>/dev/null | grep -q "$S"; do sleep 2; done
say "FASTBOOT - flashing stock kernel"
timeout 300 fastboot -s "$S" flash kernel "$STOCK" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "STOCK BOOTED - normal Android. USB can be unplugged. Good night!"
