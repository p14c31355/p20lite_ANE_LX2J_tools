#!/bin/bash
# Cycle the client + pyusb probes while the v112 boot lives; log everything.
set -u
cd ~/dev/p20-root
SER="SCV7N18927000473"
UV="/home/placeless/.hermes/bin/uv run --no-project --with pyusb python3"
for i in $(seq 1 40); do
  T=$(date +%H:%M:%S)
  C=$(timeout 8 fastboot -s "$SER" getvar serialno 2>&1 | tr -d '\r' | tail -1)
  P=$(timeout 40 $UV olog_main_read.py 2>&1 >/dev/null; echo "rc=$?")
  echo "$T client='${C:0:60}' pyusb=$P lines=$(wc -l < /tmp/olog_main.txt 2>/dev/null || echo 0)"
  cp -f /tmp/olog_main.txt /tmp/olog_probe_$i.txt 2>/dev/null || true
  sleep 20
done
date
