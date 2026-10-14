#!/bin/bash
# Clean recovery from the dark state: wait for fastboot, then simply reboot.
#
# The stock kernel is already in the partition; the dark state came from failed
# exploit attempts destabilising the running system, not from the kernel. So a
# plain `fastboot reboot` should bring Android back.
set -u
cd "$(dirname "$0")"

echo "== waiting for fastboot (Volume Down + Power on the device); up to 30 min"
for i in $(seq 1 180); do
  timeout 6 fastboot devices 2>/dev/null | grep -q . && break
  sleep 10
done

if timeout 6 fastboot devices 2>/dev/null | grep -q .; then
  echo "fastboot is up - rebooting"
  timeout 60 fastboot reboot 2>&1 | head -1
  echo "== waiting for Android (up to 20 min)"
  for i in $(seq 1 240); do
    timeout 6 adb devices 2>/dev/null | grep -qP "^\S+\tdevice$" && { echo "android is back"; break; }
    sleep 5
  done
  timeout 6 adb devices 2>/dev/null
else
  echo "fastboot never came - hold Power for ~10 s to force a reboot, then try again"
fi
