#!/bin/bash
# Wait for Android (the loop's stock restore), then re-enter fastboot via adb
# (no combo needed: the stock boot reset the failure streak, so this boot's
# park still gets a window) and deploy the log probe.
set -u
cd /home/placeless/dev/p20-root
S=SCV7N18927000473
PROBE=artifacts/fullerene-ane-log-probe-stock.img
say() { echo "[$(date '+%H:%M:%S')] $*"; }

say "armed: waiting for Android"
for i in $(seq 1 240); do
  if timeout 6 adb devices 2>/dev/null | grep -qP "^$S\s+device$"; then
    say "ANDROID_UP"
    sleep 15
    timeout 30 adb -s "$S" reboot bootloader 2>&1 | head -1
    for j in $(seq 1 90); do
      if timeout 6 fastboot devices 2>/dev/null | grep -q "^$S"; then
        say "FASTBOOT_READY - flashing probe"
        timeout 120 fastboot -s "$S" flash kernel "$PROBE" 2>&1 | tail -1
        timeout 60 fastboot -s "$S" reboot 2>&1 | head -1
        sleep 8
        mkdir -p /tmp/readout_burst && rm -f /tmp/readout_burst/*.jpg /tmp/readout_burst/done.txt
        nohup bash -c 'for i in $(seq -w 1 40); do timeout 10 ffmpeg -y -f v4l2 -input_format mjpeg -video_size 1920x1080 -i /dev/video0 -frames:v 1 "/tmp/readout_burst/r$i.jpg" 2>/dev/null; sleep 1.5; done; echo done > /tmp/readout_burst/done.txt' >/dev/null 2>&1 &
        say "probe flashed; render in ~40s - photograph now"
        exit 0
      fi
      sleep 2
    done
    say "no fastboot after adb reboot"
    exit 3
  fi
  sleep 5
done
say "ANDROID_TIMEOUT"
exit 2
