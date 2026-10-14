#!/bin/bash
# ane_autopilot.sh — combo-free experiment cycle.
# The device needs no button presses: adb gets us to the bootloader, and the
# v13 wrapper writes the BCB ("bootonce-bootloader") so the device returns to
# fastboot on its own after the observation window.
#
# usage: bash ane_autopilot.sh [cycles]
set -u
cd "$(dirname "$0")"
LOG=autopilot.log
EXP_FILE=next_experiment.txt
STOP_FILE=autopilot.stop
EXP_DEFAULT=/tmp/rd_patch/testV13.img
STOCK=firmware/stock_ramdisk_110C635.img
ANE=SCV7N18927000473
ADB="adb -s $ANE"
FB="fastboot -s $ANE"
MISC_CLEAR=firmware/misc_clear.img
SD_PATH=/storage/D4DD-4FB0/ane/

log(){ echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }

wait_adb(){ for i in $(seq 1 60); do timeout 6 $ADB shell true 2>/dev/null && return 0; sleep 5; done; return 1; }
wait_fastboot(){ local n="${1:-600}"; for i in $(seq 1 "$n"); do timeout 2 $FB devices 2>/dev/null | grep -q "$ANE" && return 0; sleep 1; done; return 1; }

for cycle in $(seq 1 "${1:-1}"); do
  [ -f "$STOP_FILE" ] && { log "stop file found; exiting"; break; }
  EXP=$(cat "$EXP_FILE" 2>/dev/null || echo "$EXP_DEFAULT")
  log "=== cycle $cycle: experiment=$EXP ==="

  if ! wait_adb; then
    log "no adb after 5 min; waiting 5 more"
    wait_adb || { log "still no adb; abort"; break; }
  fi
  log "adb ok; entering bootloader (combo-free)"
  timeout 30 $ADB reboot bootloader
  if ! wait_fastboot 40; then log "no fastboot after adb reboot; abort"; break; fi

  log "fastboot ok; flashing experiment"
  OUT=$(timeout 150 $FB flash ramdisk "$EXP" 2>&1); echo "$OUT" | tail -1 | tee -a "$LOG"
  if ! echo "$OUT" | grep -q "Finished"; then
    log "flash failed; retrying once"
    sleep 5
    OUT=$(timeout 150 $FB flash ramdisk "$EXP" 2>&1); echo "$OUT" | tail -1 | tee -a "$LOG"
  fi
  if ! echo "$OUT" | grep -q "Finished"; then
    log "experiment flash failed twice; skipping this cycle"
    timeout 30 $FB reboot; wait_adb || true
    continue
  fi
  timeout 30 $FB reboot

  log "experiment booted; waiting for the auto-return (fast catch, up to ~20 min)"
  if wait_fastboot 1000; then
    log "AUTO-RETURN WORKED (BCB mechanism valid; no combo needed)"
  else
    log "AUTO-RETURN FAILED: device wedged; a physical combo is needed. Stopping."
    break
  fi

  log "flashing stock"
  OUT=$(timeout 150 $FB flash ramdisk "$STOCK" 2>&1); echo "$OUT" | tail -1 | tee -a "$LOG"
  if ! echo "$OUT" | grep -q "Finished"; then
    log "stock flash failed; retrying once"
    sleep 5
    OUT=$(timeout 150 $FB flash ramdisk "$STOCK" 2>&1); echo "$OUT" | tail -1 | tee -a "$LOG"
  fi
  timeout 30 $FB reboot

  if ! wait_adb; then log "no adb after stock; abort"; break; fi
  log "Android up; pulling the SD"
  TS=$(date '+%m%d_%H%M%S')
  mkdir -p "sd_auto/cycle_$TS"
  sleep 15   # give vold time to mount the card
  for pr in 1 2 3 4 5 6; do
    timeout 120 $ADB pull "$SD_PATH" "sd_auto/cycle_$TS/" >/dev/null 2>&1 && break
    log "pull attempt $pr: not ready, retrying"; sleep 15
  done
  log "cycle $cycle complete; SD archived to sd_auto/cycle_$TS/"
done
log "autopilot done"
