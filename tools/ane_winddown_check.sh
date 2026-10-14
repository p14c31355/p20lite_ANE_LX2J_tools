#!/usr/bin/env bash
# One-shot: watch the 06:00 wind-down and report the final night state.
sleep 2700
cd "$(dirname "$0")"
date '+%H:%M:%S'
echo "=== runner (wind-down?) ==="
tail -6 usb_runs/night_20261003_0159.log
echo "=== phone ==="
lsusb | grep -E "18d1|12d1" || echo "not on usb"
echo "=== catcher alive? ==="
pgrep -af "ane_fast_catcher" | head -2 || echo "catcher gone"
echo "=== queue ==="
cat night_queue.txt
echo "=== probe runs (final) ==="
tail -6 usb_runs/night_probe_runs.txt 2>/dev/null
echo "=== usbcheap verdict ==="
cat usb_runs/usbcheap_verdict.txt 2>/dev/null
