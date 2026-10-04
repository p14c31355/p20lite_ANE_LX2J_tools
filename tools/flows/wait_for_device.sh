#!/bin/bash
# Block until the ANE-LX2J answers on adb or fastboot again, then exit.
#
# The phone was left wedged mid-Android-boot by the last root-shell session, so
# the morning session cannot start until someone power-cycles it (hold power
# ~10 s) and re-enables USB debugging. This script exists so that event ends the
# wait by itself - run it with notify so the completion is the reminder, rather
# than polling by hand.
set -u
DEADLINE=$(( $(date +%s) + ${1:-19800} ))   # default 5.5 h
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  ST=$(timeout 8 adb devices 2>/dev/null | awk 'NR==2{print $2}')
  if [ "$ST" = "device" ]; then
    echo "adb device is back at $(date +%T)"
    exit 0
  fi
  if [ "$ST" = "unauthorized" ]; then
    echo "device on adb but unauthorized at $(date +%T) - the on-device allow dialog is needed"
    exit 0
  fi
  if timeout 8 fastboot devices 2>/dev/null | grep -q .; then
    echo "fastboot device is back at $(date +%T)"
    exit 0
  fi
  sleep 20
done
echo "deadline reached without the device returning"
exit 1
