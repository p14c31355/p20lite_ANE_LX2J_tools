#!/bin/bash
# Screen-change watcher: while the phone sits in a frozen/static screen, the
# webcam frame stays tiny and near-constant (a uniform field compresses to
# ~2.8 KB). A real state change - the user's press, a reboot, a probe
# painting its bands, Android coming up - makes the frame size jump. This is
# the cheap "did anything happen on the phone" detector for the unattended
# night; the runner's own camera captures stay untouched (shared v4l2: we
# tolerate busy errors and retry).
cd "$(dirname "$0")" || exit 1
BASE=${1:-2790}        # the frozen blue frame's approximate size
TOL=${2:-1200}         # anything beyond this from the baseline is a change
while :; do
  [ "$(date +%H)" -ge 6 ] && [ "$(date +%H)" -lt 12 ] && exit 0   # morning quiet window
  F=/tmp/ane_screen_watch.jpg
  if timeout 20 ffmpeg -y -hide_banner -loglevel error -f v4l2 \
       -input_format mjpeg -i /dev/video0 -frames:v 1 "$F" 2>/dev/null \
     && [ -s "$F" ]; then
    SZ=$(stat -c %s "$F")
    DIFF=$((SZ > BASE ? SZ - BASE : BASE - SZ))
    if [ "$DIFF" -gt "$TOL" ]; then
      echo "[$(date +%H:%M:%S)] SCREEN CHANGED: frame ${SZ} B (baseline ~${BASE} B)" \
        | tee -a usb_runs/screen_watch.log
      cp "$F" "usb_runs/screen_changed_$(date +%m%d_%H%M%S).jpg"
      sleep 900    # changed already; do not spam, re-baseline later
      BASE=$SZ
    fi
  fi
  sleep 90
done
