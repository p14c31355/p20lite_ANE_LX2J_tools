#!/bin/bash
# ane_nightwatch.sh — long-poll recovery watcher.
# The v14 watchdog did not bite; the device sits wedged.  A wedged boot on
# this unit has been observed to complete on its own after hours (5.9 h once),
# and whenever Android or fastboot comes back we must grab the SD before
# anything overwrites it.  Polls for up to 8 hours; stops after the first
# successful pull (or a fastboot recovery + stock boot + pull).
set -u
cd "$(dirname "$0")"
LOG=nightwatch.log
SD_PATH=/storage/D4DD-4FB0/ane/
STOCK=firmware/stock_ramdisk_110C635.img
log(){ echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }

log "nightwatch start (up to 8 h)"
for i in $(seq 1 320); do
  # 1) fastboot? -> recover to stock, then pull
  if timeout 8 fastboot devices 2>/dev/null | grep -q .; then
    log "fastboot appeared on poll $i"
    timeout 150 fastboot flash ramdisk "$STOCK" 2>&1 | tail -1 | tee -a "$LOG"
    timeout 30 fastboot reboot
    for j in $(seq 1 60); do timeout 6 adb devices 2>/dev/null | grep -qP '\tdevice$' && break; sleep 5; done
    TS=$(date '+%m%d_%H%M%S')
    mkdir -p "sd_auto/recovery_$TS"
    timeout 180 adb pull "$SD_PATH" "sd_auto/recovery_$TS/" 2>&1 | tail -1 | tee -a "$LOG"
    log "recovery pull done -> sd_auto/recovery_$TS/"
    exit 0
  fi
  # 2) adb? -> pull directly, stop
  if timeout 8 adb devices 2>/dev/null | grep -qP '\tdevice$'; then
    log "adb appeared on poll $i (self-recovered boot)"
    TS=$(date '+%m%d_%H%M%S')
    mkdir -p "sd_auto/recovery_$TS"
    timeout 180 adb pull "$SD_PATH" "sd_auto/recovery_$TS/" 2>&1 | tail -1 | tee -a "$LOG"
    log "recovery pull done -> sd_auto/recovery_$TS/ (device left in Android)"
    exit 0
  fi
  sleep 90
done
log "nightwatch gave up after 8 h (device still wedged; morning combo needed)"
