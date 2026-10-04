#!/bin/bash
# V21_LOOP.sh N — v21 サイクルを N 回連続で回す（ユーザー操作ゼロ）。
# 各サイクル: [adb reboot bootloader → flash v21 → reboot] →
#   ラッパーが M-rb (clean restart) → LK が fastboot を開く →
#   ane_awake.sh (守衛) が捕捉 → stock 焼き → Android → SD pull
# 使い方: bash V21_LOOP.sh 3
# 注意: eRecovery (1 インターフェースの 12d1:107e) に落ちた場合のみ
#       完全電源 OFF → fastboot のコンボが 1 回必要。
set -u
cd /home/placeless/dev/p20-root
ANE=SCV7N18927000473
IMG=/tmp/rd_patch/testV21.img
N="${1:-3}"
for i in $(seq 1 "$N"); do
  echo "===== cycle $i/$N start $(date '+%H:%M:%S') ====="
  if ! timeout 10 adb -s $ANE get-state >/dev/null 2>&1; then
    echo "!! adb 不達 = eRecovery の可能性。コンボ (完全電源 OFF → 電源+音量下) が必要です"
    break
  fi
  timeout 30 adb -s $ANE reboot bootloader
  sleep 10
  timeout 150 fastboot -s $ANE flash ramdisk "$IMG" 2>&1 | tail -2
  timeout 30 fastboot -s $ANE reboot 2>&1 | tail -1
  echo "flashed $(date '+%H:%M:%S'); watcher (foreground)"
  bash ane_awake.sh
  D=$(ls -td sd_auto/cycle_*/ | head -1)
  echo "pull: $D"
  tail -3 "$D/ane/report.txt" 2>/dev/null
  NIF=$(lsusb -d 12d1:107e -v 2>/dev/null | grep bNumInterfaces)
  echo "USB: ${NIF:-なし}"
  echo "===== cycle $i/$N done $(date '+%H:%M:%S') ====="
done
echo "loop complete"
