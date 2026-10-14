#!/bin/bash
# ane_awake.sh — recovery watcher: once the user escapes eRecovery (combo),
# catch either fastboot or Android, restore stock, and pull the SD archive.
# Serial-pinned: safe with other devices (Bramble) attached.
cd "$(dirname "$0")"
ANE=SCV7N18927000473
LOG=awake.log
log(){ echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }

log "awake: watching up to ~5.5 h for fastboot/adb (fast catch: 1.5 s cadence)"
GOT=""
for i in $(seq 1 13000); do
  if timeout 2 fastboot -s $ANE devices 2>/dev/null | grep -q "$ANE"; then
    GOT=fastboot; break
  fi
  if timeout 3 adb -s $ANE shell true 2>/dev/null; then
    GOT=adb; break
  fi
  sleep 1.5
done

if [ "$GOT" = fastboot ]; then
  log "fastboot appeared; flashing stock ramdisk"
  timeout 150 fastboot -s $ANE flash ramdisk firmware/stock_ramdisk_110C635.img 2>&1 | tail -1 | tee -a "$LOG"
  timeout 30 fastboot -s $ANE reboot
  log "reboot issued; waiting for Android"
  for j in $(seq 1 60); do timeout 6 adb -s $ANE shell true 2>/dev/null && break; sleep 5; done
elif [ "$GOT" = adb ]; then
  log "Android (adb) already up"
else
  log "40 min passed without fastboot/adb; giving up (morning job will report)"
  exit 0
fi

TS=$(date '+%m%d_%H%M%S')
DEST="sd_auto/cycle_v17_$TS"
mkdir -p "$DEST"
for pr in 1 2 3 4 5 6; do
  if timeout 120 adb -s $ANE pull /storage/D4DD-4FB0/ane/ "$DEST/" >/dev/null 2>&1; then
    log "SD pulled to $DEST"; break
  fi
  log "pull attempt $pr failed; retry in 15s"; sleep 15
done
log "awake done; files:"
ls -la "$DEST/ane/" 2>/dev/null | tail -15 | tee -a "$LOG"
