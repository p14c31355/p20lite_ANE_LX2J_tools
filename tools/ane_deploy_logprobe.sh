#!/bin/bash
# Deploy the new log probe on the next fastboot window (armed now).
# On FASTBOOT_READY: flash artifacts/fullerene-ane-log-probe-stock.img, arm the
# 1080p burst, wait for the next window, then leave the device to the loop.
set -u
cd /home/placeless/dev/p20-root
S=SCV7N18927000473
PROBE=artifacts/fullerene-ane-log-probe-stock.img
say() { echo "[$(date '+%H:%M:%S')] $*"; }

say "armed: waiting for fastboot (combo)"
for i in $(seq 1 900); do
  if timeout 6 fastboot devices 2>/dev/null | grep -q "^$S"; then
    say "FASTBOOT_READY"
    timeout 120 fastboot -s "$S" flash kernel "$PROBE" 2>&1 | tail -1
    timeout 60 fastboot -s "$S" reboot 2>&1 | head -1
    sleep 8
    mkdir -p /tmp/readout_burst && rm -f /tmp/readout_burst/*.jpg /tmp/readout_burst/done.txt
    nohup bash -c 'for i in $(seq -w 1 40); do timeout 10 ffmpeg -y -f v4l2 -input_format mjpeg -video_size 1920x1080 -i /dev/video0 -frames:v 1 "/tmp/readout_burst/r$i.jpg" 2>/dev/null; sleep 1.5; done; echo done > /tmp/readout_burst/done.txt' >/dev/null 2>&1 &
    say "probe flashed; burst armed; render should appear ~40s"
    exit 0
  fi
  sleep 2
done
say "WATCH_TIMEOUT"
exit 1
