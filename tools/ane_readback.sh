#!/bin/bash
# One-shot readback: from fastboot -> flash stock + misc_clear -> boot -> pull SD.
set -u
cd "$(dirname "$0")"
STOCK=firmware/stock_ramdisk_110C635.img
MISC_CLEAR=firmware/misc_clear.img
SD_PATH=/storage/D4DD-4FB0/ane/
log(){ echo "[$(date '+%H:%M:%S')] $*"; }
log "readback: flashing stock + misc_clear"
timeout 150 fastboot flash ramdisk "$STOCK" 2>&1 | tail -1
timeout 60 fastboot flash misc "$MISC_CLEAR" 2>&1 | tail -1
timeout 30 fastboot reboot
for i in $(seq 1 60); do timeout 6 adb devices 2>/dev/null | grep -qP '\tdevice$' && break; sleep 5; done
TS=$(date '+%m%d_%H%M%S')
mkdir -p "sd_auto/cycle_$TS"
timeout 180 adb pull "$SD_PATH" "sd_auto/cycle_$TS/" 2>&1 | tail -1
log "readback complete -> sd_auto/cycle_$TS/"
