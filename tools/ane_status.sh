#!/bin/bash
# One-shot status line for the night loop. Shows the runner, the queue, the
# USB-default flow, the device fingerprint and every watcher's liveness.
cd "$(dirname "$0")" || exit 1
LOG=$(ls -t usb_runs/night_*.log 2>/dev/null | head -1)
echo "=== ANE night status $(date '+%m-%d %H:%M:%S') ==="
STOP=$(grep -o 'stop at [^;]*' "$LOG" 2>/dev/null | head -1)
echo "runner   : $(pgrep -cf '[a]ne_night.sh') procs; $STOP"
echo "queue    : $(wc -l < night_queue.txt) entries (pass file: $(wc -l < night_queue.probes.pending))"
if [ -f .usb_default_done ]; then echo "usb flow : DONE (persist = $(timeout 6 adb shell getprop persist.sys.usb.config 2>/dev/null | tr -d '\r'))"
elif [ -f .usb_flow_gaveup ]; then echo "usb flow : gave up"
else echo "usb flow : pending (attempts file: $(cat .usb_default_attempts 2>/dev/null))"; fi
echo "device   : $(lsusb | grep -oE '12d1:107e|18d1:d00d' | head -1 || echo dark) / fastboot: $(timeout 5 fastboot devices 2>/dev/null | head -1 || echo no) / adb: $(timeout 5 adb devices 2>/dev/null | awk 'NR==2{print $2}' || echo no)"
for s in heartbeat loop_refill stall_watch watch_event l2_watch usbflow_watch; do
  if pgrep -f "bash [a]ne_${s}.sh" >/dev/null; then echo "  OK   $s"; else echo "  DEAD $s"; fi
done
echo "--- runner tail:"
tail -3 "$LOG" 2>/dev/null
