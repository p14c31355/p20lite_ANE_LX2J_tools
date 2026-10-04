#!/bin/bash
# One-shot eRecovery-kill device test (stepmarks3) + mark readout (paint-probe-stock).
#
# Chain: [wait Android] -> [settle] -> flash stepmarks3 -> boot -> arm catcher
#        -> wait for the fastboot window (kill held) or timeout (report state)
#        -> [settle] -> flash paint-probe-stock -> boot -> camera burst -> arm catcher
#        -> log the readout paths.
#
# Run from ~/dev/p20-root. Every step prints [HH:MM:SS] lines to stdout and to
# usb_runs/kill_test_<stamp>.log. Exit codes: 0 = full chain ran,
# 2 = the kill test produced no fastboot window (state printed; a combo may be needed).
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
LOG=usb_runs/kill_test_$(date '+%m%d_%H%M').log
mkdir -p usb_runs
say() { echo "[$(date '+%H:%M:%S')] $*"; echo "[$(date '+%H:%M:%S')] $*" >> "$LOG"; }
android_up() { timeout 8 adb -s "$S" shell true >/dev/null 2>&1; }
state() { lsusb | grep -E "12d1|18d1" | sed 's/^/    /' | tee -a "$LOG"; }

say "== 0. wait for Android (the combo + the armed catcher restore it)"
for _ in $(seq 1 90); do android_up && break; sleep 5; done
if android_up; then say "   android is up"; else say "FAIL: no Android after ~8 min"; exit 1; fi
say "   settle 240 s (LK volatile-counter cooling insurance)"
sleep 240

say "== 1. flash stepmarks3 (early-vector kill build)"
timeout 30 adb -s "$S" reboot bootloader || true
sleep 12
timeout 120 fastboot -s "$S" flash kernel artifacts/fullerene-ane-stepmarks3-stock.img 2>&1 | tail -2 | tee -a "$LOG"
timeout 30 fastboot -s "$S" reboot | tail -1
say "   booted; arming the catcher"
bash ane_fast_catch.sh > "usb_runs/kill_test_catch1.log" 2>&1 &
C1=$!
for _ in $(seq 1 72); do kill -0 "$C1" 2>/dev/null || break; sleep 10; done
if kill -0 "$C1" 2>/dev/null; then
  kill "$C1" 2>/dev/null
  say "   NO fastboot window in 12 min; current state:"
  state
  say "STOP: the kill test did not reach fastboot (kill ineffective or counter hot - see V21_STATE.md)"
  exit 2
fi
wait "$C1"; RC=$?
if [ "$RC" = 0 ]; then
  say "   kill test: fastboot window caught -> stock restored:"
  tail -4 usb_runs/kill_test_catch1.log | sed 's/^/    /' | tee -a "$LOG"
else
  say "   catcher exited rc=$RC (unexpected); state:"
  state
  exit 2
fi

say "== 2. settle 180 s, then flash paint-probe-stock + camera burst"
sleep 180
timeout 30 adb -s "$S" reboot bootloader || true
sleep 12
timeout 120 fastboot -s "$S" flash kernel artifacts/fullerene-ane-paint-probe-stock.img 2>&1 | tail -2 | tee -a "$LOG"
timeout 30 fastboot -s "$S" reboot | tail -1
sleep 8
mkdir -p /tmp/paint_burst && rm -f /tmp/paint_burst/*.jpg
for i in $(seq -w 1 40); do
  timeout 8 ffmpeg -y -f v4l2 -video_size 640x480 -i /dev/video0 -frames:v 1 "/tmp/paint_burst/p$i.jpg" 2>/dev/null
  sleep 1.5
done
say "   burst done: $(ls /tmp/paint_burst/*.jpg 2>/dev/null | wc -l) frames"
python3 ane_cam_read.py --frames 4 2>&1 | tail -4 | sed 's/^/    /' | tee -a "$LOG"
say "   arming the catcher for the paint probe's fallback"
bash ane_fast_catch.sh > "usb_runs/kill_test_catch2.log" 2>&1 &
C2=$!
for _ in $(seq 1 72); do kill -0 "$C2" 2>/dev/null || break; sleep 10; done
if kill -0 "$C2" 2>/dev/null; then
  kill "$C2" 2>/dev/null
  say "   paint probe: no window in 12 min; state:"
  state
fi
say "DONE. log: $LOG ; photos: /tmp/paint_burst ; catch logs: usb_runs/kill_test_catch{1,2}.log"
