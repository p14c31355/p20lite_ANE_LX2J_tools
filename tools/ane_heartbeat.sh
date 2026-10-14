#!/bin/bash
# Heartbeat: every 30 minutes, append one compact status line to the night doc,
# so the record shows continuous operation through the night (the user reads
# the doc in the morning). Append-only; silent otherwise.
set -u
cd "$(dirname "$0")"
DOC=docs/ANE_NIGHT_20261002.md
while :; do
  if lsusb | grep -q "18d1:d00d"; then st=fastboot
  elif timeout 6 adb devices 2>/dev/null | grep -qP '^\S+\tdevice$'; then st=adb
  elif lsusb | grep -q "12d1:107e"; then
    st="gadget$(lsusb -v -d 12d1:107e 2>/dev/null | grep -cE bInterfaceNumber)if"
  else st=dark; fi
  printf -- "- %s 端末=%s キュー残=%s ランナー=%s\n" \
    "$(date '+%m-%d %H:%M')" "$st" \
    "$(wc -l < night_queue.txt 2>/dev/null || echo '?')" \
    "$(ps aux | grep -c '[a]ne_night.sh')" >> "$DOC"
  sleep 1800
done
