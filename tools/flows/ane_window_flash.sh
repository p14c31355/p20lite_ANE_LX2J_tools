#!/bin/bash
# Window flasher: catch the loader's fastboot window and flash a GIVEN image
# instead of the stock kernel (the chain step for experiment sequences).
#
# Usage: ane_window_flash.sh IMAGE
#   IMAGE = path to a boot image (e.g. artifacts/fullerene-ane-marks-final-all-stock.img)
# On a catch: flash IMAGE, reboot, then start a 40-frame camera burst into
# /tmp/readout_burst so the run's visual readout is captured automatically.
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473

IMAGE="${1:?usage: ane_window_flash.sh IMAGE}"
[ -f "$IMAGE" ] || { echo "no such image: $IMAGE" >&2; exit 3; }

say() { echo "[$(date '+%H:%M:%S')] $*"; }

burst() {
  mkdir -p /tmp/readout_burst
  rm -f /tmp/readout_burst/*.jpg /tmp/readout_burst/done.txt
  nohup bash -c 'for i in $(seq -w 1 40); do timeout 10 ffmpeg -y -f v4l2 -input_format mjpeg -video_size 1920x1080 -i /dev/video0 -frames:v 1 "/tmp/readout_burst/r$i.jpg" 2>/dev/null; sleep 1.5; done; echo "readout burst done: $(ls /tmp/readout_burst/*.jpg 2>/dev/null | wc -l) frames" > /tmp/readout_burst/done.txt' >/dev/null 2>&1 &
}

fire() {
  say "fastboot is up -> flashing $IMAGE"
  timeout 120 fastboot -s "$S" flash kernel "$IMAGE" 2>&1 | tail -2
  timeout 60 fastboot -s "$S" reboot 2>&1 | head -1
  burst
  say "flashed and rebooting; camera burst armed (1080p mjpeg)"
  return 0
}

if timeout 6 fastboot devices 2>/dev/null | grep -q . ; then
  fire
  exit $?
fi

say "streaming the kernel log for the fastboot signature (idVendor=18d1)"
while IFS= read -r line; do
  case "$line" in
    *"idVendor=18d1"*)
      sleep 1
      if timeout 6 fastboot devices 2>/dev/null | grep -q . ; then
        fire
        exit 0
      fi
      ;;
  esac
done < <(timeout 3600 journalctl -k -f -n 0 2>/dev/null)
say "window closed without a catch"
exit 2
