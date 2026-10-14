#!/usr/bin/env bash
# 夜間定常ループ: v280コントロールを維持し、各ブートでCNXN収集→magic reset→LK自動再フラッシュ。
# 収集物は rings_night/night1011/ へ。エンジンは5分 stall したら oem crash で救出。
cd /home/placeless/dev/p20-root || exit 1
LOG="logs/night1011_$(date +%H%M%S).log"
exec >>"$LOG" 2>&1
S=SCV7N18927000473
mkdir -p rings_night/night1011
C=0
STALL=0
while true; do
  P=$(cat /sys/bus/usb/devices/1-1/product 2>/dev/null)
  if [ "$P" = "Fastboot2.0" ]; then
    echo "[$(date +%H:%M:%S)] LK -> flash v280"
    fastboot -s "$S" flash kernel artifacts/fullerene-ane-v280-revert.img >/dev/null 2>&1
    sleep 2
    fastboot -s "$S" reboot >/dev/null 2>&1
    STALL=0
    sleep 60
    continue
  fi
  if [ "$P" = "ANE fastboot" ]; then
    STALL=0
    C=$((C+1))
    OUT="rings_night/night1011/n_${C}_$(date +%H%M).bin"
    ~/.hermes/bin/uv run --with pyusb --no-project python3 adb_cycle.py log "$OUT" 2>&1 | tail -1
    if [ -s "$OUT" ]; then
      echo "[$(date +%H:%M:%S)] collected $OUT ($(stat -c%s "$OUT")B)"
    fi
    sleep 30
    continue
  fi
  STALL=$((STALL+1))
  if [ $STALL -gt 60 ]; then
    echo "[$(date +%H:%M:%S)] stall rescue: oem crash"
    timeout 20 ~/.hermes/bin/uv run --with pyusb --no-project python3 adb_cycle.py crash 2>&1 | tail -1
    STALL=0
  fi
  sleep 5
done
