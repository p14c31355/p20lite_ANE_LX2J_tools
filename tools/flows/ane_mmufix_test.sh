#!/bin/bash
# mmu-fix device test chain (2026-10-04).
#
# Phase 1: flash the mmu-fix kernel (per-platform MMIO ranges) -> boot ->
#          wait for its park's fastboot window (the eRecovery-kill path).
# Phase 2: in that window, window_flash swaps in the READER
#          (text-fix-stock = text console) which renders the scratch record
#          (V0..V9 + RC=ANEM/count/marks) -> 1080p MJPEG burst into
#          /tmp/readout_burst.
# Phase 3: arm the catcher for the reader's own fallback -> stock restored.
#
# Usage: run from ~/dev/p20-root with the device already in fastboot
# (the manual combo after eRecovery). Prints [HH:MM:SS] to stdout and to
# usb_runs/mmufix_<stamp>.log.
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
LOG=usb_runs/mmufix_$(date '+%m%d_%H%M').log
mkdir -p usb_runs
say() { echo "[$(date '+%H:%M:%S')] $*"; echo "[$(date '+%H:%M:%S')] $*" >> "$LOG"; }
state() { lsusb | grep -E "12d1|18d1" | sed 's/^/    /' | tee -a "$LOG"; }

say "== 1. mmu-fix flash (device must already be in fastboot)"
if ! timeout 6 fastboot devices 2>/dev/null | grep -q .; then
  say "FAIL: no fastboot device; do the combo (power OFF -> Vol-Down+Power) first"
  exit 2
fi
timeout 120 fastboot -s "$S" flash kernel artifacts/fullerene-ane-mmu-fix-stock.img 2>&1 | tail -2 | tee -a "$LOG"
timeout 30 fastboot -s "$S" reboot | tail -1
say "   booted; arming window_flash -> reader + 1080p burst"

bash ane_window_flash.sh artifacts/fullerene-ane-text-fix-stock.img >> "$LOG" 2>&1 &
W=$!
for _ in $(seq 1 180); do kill -0 "$W" 2>/dev/null || break; sleep 10; done
if kill -0 "$W" 2>/dev/null; then
  kill "$W" 2>/dev/null
  say "   no fastboot window in 30 min; state:"
  state
  say "STOP: mmu-fix produced no window (unexpected; see V21_STATE.md)"
  exit 2
fi
wait "$W"; RC=$?
if [ "$RC" != 0 ]; then
  say "   window_flash rc=$RC; state:"
  state
  exit 2
fi
say "   reader flashed; waiting for the 1080p burst to finish"
for _ in $(seq 1 72); do [ -f /tmp/readout_burst/done.txt ] && break; sleep 5; done
say "   burst: $(cat /tmp/readout_burst/done.txt 2>/dev/null || echo incomplete)"

say "== 3. arm the catcher for the reader's fallback -> stock restore"
bash ane_fast_catch.sh > "usb_runs/mmufix_catch.log" 2>&1 &
C=$!
for _ in $(seq 1 150); do kill -0 "$C" 2>/dev/null || break; sleep 10; done
if kill -0 "$C" 2>/dev/null; then
  kill "$C" 2>/dev/null
  say "   no window in 25 min; state:"
  state
else
  tail -4 usb_runs/mmufix_catch.log | sed 's/^/    /' | tee -a "$LOG"
fi
say "DONE. log: $LOG ; photos: /tmp/readout_burst"
