#!/bin/bash
# Collect 4 more ring tails via the zero-delay path (watcher first, then reboot).
set +m
cd ~/dev/p20-root
UV=/home/placeless/.hermes/bin/uv
for i in 1 2 3 4; do
  "$UV" run --with pyusb --no-project python3 zero3.py "rings_night/v306_zero3_b${i}.bin" > /tmp/zero3_b$i.log 2>&1 &
  Z=$!
  sleep 1
  fastboot reboot > /dev/null 2>&1
  wait $Z
  SZ=$(stat -c %s "rings_night/v306_zero3_b${i}.bin" 2>/dev/null || echo 0)
  echo "boot$i size=$SZ"
done
