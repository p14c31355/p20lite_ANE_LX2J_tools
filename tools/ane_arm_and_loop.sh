#!/bin/bash
# Arm: wait for the next fastboot (combo), then hand the whole cycle to the
# log-dump loop with the given experiment image.
#   ane_arm_and_loop.sh artifacts/fullerene-ane-stepmarks9-stock.img
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
EXP="${1:?usage: ane_arm_and_loop.sh EXP_IMG}"
say() { echo "[$(date '+%H:%M:%S')] $*"; }

say "armed: waiting for fastboot (combo) to start the loop with $EXP"
for i in $(seq 1 900); do
  if timeout 6 fastboot devices 2>/dev/null | grep -q "^$S"; then
    say "FASTBOOT_READY - starting loop"
    exec bash ane_logloop.sh "$EXP" 1
  fi
  sleep 2
done
say "WATCH_TIMEOUT"
exit 1
