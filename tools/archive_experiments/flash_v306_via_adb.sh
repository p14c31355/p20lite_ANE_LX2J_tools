#!/bin/bash
# adb reboot bootloader -> catch LK (Fastboot2.0) -> flash v306 -> reboot
set +m
IMG="$HOME/dev/p20-root/artifacts/fullerene-ane-v306-quietdetector.img"
LOG="$HOME/dev/p20-root/logs/v306_flash_$(date +%H%M%S).log"
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$LOG"; }
log "=== v306 flash via adb reboot bootloader ==="
adb reboot bootloader >>"$LOG" 2>&1
log "reboot-bootloader sent, waiting for LK (Fastboot2.0)"
for i in $(seq 1 60); do
  P=$(timeout 3 lsusb -v -d 18d1:d00d 2>/dev/null | grep -o 'Fastboot2\.0' | head -1)
  if [ -n "$P" ]; then
    log "LK window up (lsusb iProduct=Fastboot2.0) -> flash v306"
    timeout 120 fastboot flash kernel "$IMG" >>"$LOG" 2>&1
    RC=$?
    log "flash rc=$RC"
    if [ $RC -eq 0 ]; then
      timeout 15 fastboot reboot >>"$LOG" 2>&1
      log "reboot sent - v306 is now the resident kernel"
      exit 0
    fi
  fi
  sleep 1
done
log "TIMEOUT: LK window never appeared"
exit 1
