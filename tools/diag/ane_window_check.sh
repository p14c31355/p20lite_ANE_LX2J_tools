#!/usr/bin/env bash
# One-shot: wait out the park's ~7-minute self-reset hypothesis window, then
# dump everything that decides whether the catcher got the next window.
sleep 240
cd "$(dirname "$0")"
date '+%H:%M:%S'
echo "=== catcher log ==="
tail -5 usb_runs/fast_catcher.log
echo "=== phone now ==="
lsusb | grep -E "12d1|18d1" || echo "not on usb"
echo "=== usb events since 02:25 ==="
journalctl -k --since "02:25:00" --no-pager 2>/dev/null \
  | grep -viE "snap.discord|audit" | grep -iE "usb 1-1.*(disconnect|New USB)" | tail -8
echo "=== runner ==="
tail -3 usb_runs/night_20261003_0159.log
echo "=== stepmarks2 still in queue? ==="
head -3 night_queue.txt
