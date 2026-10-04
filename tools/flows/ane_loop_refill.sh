#!/bin/bash
# Keep the verification loop fed until the morning: whenever the queue runs
# dry, drop the next pass in (the probe set + a trailing RESTORE, which gives
# an Android health interlude and exercises the restore path every pass).
# The runner reads the queue live, so refills are picked up on its next
# fastboot or adb window without touching the runner itself.
#
# Retires itself at 05:40 so the final pass can drain and the runner's
# 06:00 wind-down finds the queue empty and settles the phone into Android.
set -u
cd "$(dirname "$0")"
PASS=night_queue.probes.pending
PASSES=0
EMPTY_SINCE=""
# Interleave the USB-default flow with the passes. The flow only gets a
# usable adb window on a freshly restored Android boot, and the pass file
# ends with a RESTORE for exactly that reason - so after each pass the queue
# stays empty for a while before the next pass is dropped in, and the
# usbflow watcher spends that window on the exploit. 15 minutes covers one
# full flow attempt (reboot-free: fresh boot + settle + the long poll).
# A naive "refill as soon as empty" would hand the runner the next probe on
# the first adb sighting and yank the phone back to fastboot before the flow
# could even run.
REFILL_DELAY=900
# next occurrence of a wall-clock time, today or tomorrow (the naive
# "today HH:MM" is in the past for every evening launch).
next_at() { local t n; t=$(date -d "today $1" +%s); n=$(date +%s); [ "$n" -ge "$t" ] && t=$(date -d "tomorrow $1" +%s); echo "$t"; }
while :; do
  NOW=$(date +%s)
  STOP=$(next_at 05:40)
  [ "$NOW" -ge "$STOP" ] && { echo "[$(date +%H:%M:%S)] 05:40 - no more refills, letting the loop drain" >> usb_runs/loop_refill.log; exit 0; }
  if [ ! -s night_queue.txt ] && [ -s "$PASS" ] \
     && ! pgrep -f "[a]ne_set_usb_default.sh" >/dev/null; then
    [ -z "$EMPTY_SINCE" ] && EMPTY_SINCE=$NOW
    if [ $((NOW - EMPTY_SINCE)) -ge "$REFILL_DELAY" ]; then
      cp "$PASS" night_queue.txt
      PASSES=$((PASSES + 1))
      echo "[$(date +%H:%M:%S)] refilled queue with $(wc -l < night_queue.txt) entries (pass $PASSES)" >> usb_runs/loop_refill.log
      EMPTY_SINCE=""
    fi
  else
    EMPTY_SINCE=""
  fi
  sleep 30
done
