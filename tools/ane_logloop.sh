#!/bin/bash
# Log-dump verification loop (2026-10-04, user-directed design).
#
# One cycle:
#   [fastboot] -> flash the experiment kernel -> boot (parks; eRecovery kill) ->
#   fastboot window -> flash STOCK (a good boot resets the LK's failure streak) ->
#   Android -> adb reboot bootloader -> flash the LOG PROBE (fresh streak: its
#   park is again a first failure, so it gets its own window) -> its render is
#   captured by a 1080p burst -> window -> stock -> Android -> pull the SD.
#
# The screen render is the payload: the log probe draws the durable log tail
# (the uart tee) plus the mark record. Frames land in /tmp/readout_burst.
#
# Usage: bash ane_logloop.sh <EXPERIMENT_IMG> [CYCLES]
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
EXP="${1:?usage: ane_logloop.sh EXP_IMG [CYCLES]}"
CYCLES="${2:-1}"
PROBE=artifacts/fullerene-ane-log-probe-stock.img
STOCK=firmware/kernel_stock.bin
LOG=usb_runs/logloop_$(date '+%m%d_%H%M').log
mkdir -p usb_runs
say() { echo "[$(date '+%H:%M:%S')] $*"; echo "[$(date '+%H:%M:%S')] $*" >> "$LOG"; }

wait_fastboot() {  # $1 = max seconds
  local i
  for i in $(seq 1 "$1"); do
    timeout 6 fastboot devices 2>/dev/null | grep -q "^$S" && return 0
    sleep 1
  done
  return 1
}
wait_android() {
  local i
  for i in $(seq 1 120); do
    timeout 6 adb devices 2>/dev/null | grep -qP "^$S\s+device$" && return 0
    sleep 5
  done
  return 1
}
flash_kernel() {  # $1 = image
  timeout 120 fastboot -s "$S" flash kernel "$1" 2>&1 | tail -2 | tee -a "$LOG"
  timeout 60 fastboot -s "$S" reboot 2>&1 | head -1
}
burst() {
  mkdir -p /tmp/readout_burst && rm -f /tmp/readout_burst/*.jpg /tmp/readout_burst/done.txt
  nohup bash -c 'for i in $(seq -w 1 40); do timeout 10 ffmpeg -y -f v4l2 -input_format mjpeg -video_size 1920x1080 -i /dev/video0 -frames:v 1 "/tmp/readout_burst/r$i.jpg" 2>/dev/null; sleep 1.5; done; echo done > /tmp/readout_burst/done.txt' >/dev/null 2>&1 &
}
pull_sd() {
  sleep 20
  local label i
  for i in $(seq 1 6); do
    label=$(timeout 20 adb -s "$S" shell ls /storage/ 2>/dev/null | tr -d '\r' | grep -v '^$' | head -1)
    [ -n "$label" ] && break
    sleep 10
  done
  if [ -n "${label:-}" ]; then
    mkdir -p sd_auto
    timeout 120 adb -s "$S" pull "/storage/$label/ane/" "sd_auto/$label-$(date '+%m%d_%H%M')/" >> "$LOG" 2>&1 \
      && say "   SD pulled ($label)" || say "   SD pull failed"
  else
    say "   no SD label visible"
  fi
}

for cycle in $(seq 1 "$CYCLES"); do
  say "=== cycle $cycle/$CYCLES"

  if ! wait_fastboot 20; then
    say "-- no fastboot; trying adb reboot bootloader"
    timeout 30 adb -s "$S" reboot bootloader || true
    wait_fastboot 90 || { say "FAIL: no fastboot - combo needed"; exit 2; }
  fi

  say "-- experiment flash: $EXP"
  flash_kernel "$EXP"
  say "-- waiting for its park's fastboot window (~5 min)"
  wait_fastboot 330 || { say "no window; state:"; lsusb | grep -E '12d1|18d1' | tee -a "$LOG"; exit 2; }

  say "-- stock (streak reset)"
  flash_kernel "$STOCK"
  wait_android || say "   android slow"
  sleep 15
  pull_sd

  say "-- combo-free re-entry + log probe"
  timeout 30 adb -s "$S" reboot bootloader || true
  wait_fastboot 90 || { say "FAIL: no fastboot for probe"; exit 3; }
  flash_kernel "$PROBE"
  sleep 8
  burst
  say "   probe rendering; burst armed (frames: /tmp/readout_burst)"
  say "-- waiting for the probe's window (~10 min; its screen hold is long)"
  wait_fastboot 600 || { say "no probe window; state:"; lsusb | grep -E '12d1|18d1' | tee -a "$LOG"; exit 3; }

  say "-- stock restore + final pull"
  flash_kernel "$STOCK"
  wait_android || say "   android slow"
  sleep 15
  pull_sd
  say "=== cycle $cycle done (frames: $(ls /tmp/readout_burst/*.jpg 2>/dev/null | wc -l))"
done
say "loop complete"
