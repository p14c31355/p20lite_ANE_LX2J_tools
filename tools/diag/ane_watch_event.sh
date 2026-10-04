#!/bin/bash
# One-shot event watcher for the night. Exits (printing why) when the phone's
# USB state changes or the runner's log grows; relaunch after each catch. The
# point is to turn "wait for the phone to do something" into a single blocking
# wait instead of a polling loop.
set -u
cd "$(dirname "$0")"
STATE_FILE=/tmp/ane_watch.state
prev_state=$( [ -f "$STATE_FILE" ] && cat "$STATE_FILE" || echo "" )

latest_log() { ls -t usb_runs/night_*.log 2>/dev/null | head -1; }
LOG=$(latest_log)
prev_size=$(stat -c %s "$LOG" 2>/dev/null || echo 0)

device_state() {
  if lsusb | grep -q "18d1:d00d"; then echo fastboot; return; fi
  if timeout 8 adb devices 2>/dev/null | grep -qP '^\S+\tdevice$'; then echo adb; return; fi
  if lsusb | grep -q "12d1:107e"; then
    echo "gadget$(lsusb -v -d 12d1:107e 2>/dev/null | grep -cE bInterfaceNumber)"
    return
  fi
  echo dark
}

while :; do
  st=$(device_state)
  if [ "$st" != "$prev_state" ]; then
    echo "$(date +%H:%M:%S) STATE ${prev_state:-unknown} -> $st"
    echo "$st" > "$STATE_FILE"
    exit 0
  fi
  new=$(latest_log)
  size=$(stat -c %s "$new" 2>/dev/null || echo 0)
  if [ "$new" != "$LOG" ] || [ "$size" != "$prev_size" ]; then
    echo "$(date +%H:%M:%S) RUNNER ACTIVE: $new"
    tail -4 "$new"
    LOG=$new; prev_size=$size
    exit 0
  fi
  sleep 20
done
