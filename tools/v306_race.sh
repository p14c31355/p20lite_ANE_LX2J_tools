#!/bin/bash
# v306 window racer: flash -> watch for the clean product line at 0.5 s
# granularity -> fire the CNXN immediately (the quiet detector gives the
# conversation ~1-3 real seconds before it cycles D+).
# Usage: v306_race.sh [cycles]
set +m
cd ~/dev/p20-root
IMG=artifacts/fullerene-ane-v306-quietdetector.img
CYC="${1:-6}"
LOG=logs/v306_race_$(date +%H%M%S).log
UV=/home/placeless/.hermes/bin/uv
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$LOG"; }
lk_up(){ lsusb -v -d 18d1:d00d 2>/dev/null | grep -qi "iProduct.*Fastboot2.0"; }

log "=== v306 race start, cycles=$CYC ==="
for c in $(seq 1 "$CYC"); do
  # 1. wait for a loader window (or the boot already running)
  for i in $(seq 1 120); do
    lk_up && break
    sleep 1
  done
  if lk_up; then
    log "c$c: LK up -> flash v306"
    timeout 60 fastboot flash kernel "$IMG" >>"$LOG" 2>&1
    timeout 15 fastboot reboot >>"$LOG" 2>&1
  else
    log "c$c: no LK in 120 s; boot may be live - trying collect anyway"
  fi
  # 2. watch the journal for THIS boot's clean product line
  BASE=$(journalctl -k --no-pager | grep -c 'Product: ANE fastboot')
  HIT=0
  for i in $(seq 1 120); do
    N=$(journalctl -k --no-pager | grep -c 'Product: ANE fastboot')
    if [ "$N" -gt "$BASE" ]; then
      HIT=1
      log "c$c: clean product line at $(date +%H:%M:%S); firing CNXN"
      break
    fi
    lk_up && { log "c$c: LK appeared before product"; break; }
    sleep 0.5
  done
  if [ "$HIT" = "1" ]; then
    timeout 40 "$UV" run --with pyusb --no-project python3 adb_cycle.py log "rings_night/v306_race_c${c}.bin" >>"$LOG" 2>&1
    RC=$?
    SZ=$(stat -c %s "rings_night/v306_race_c${c}.bin" 2>/dev/null || echo 0)
    log "c$c: adb_cycle rc=$RC size=$SZ"
  fi
done
log "=== race done ==="
