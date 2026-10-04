#!/bin/bash
# Root helper: logical USB unplug/replug for the ANE-LX2J's port.
#
# The eRecovery presents a 12d1:107e gadget and, judged by its periodic
# re-enumerations, runs some state machine that may well treat "the PC
# disappeared" as a signal to give up and reboot. Testing that needs the
# ability to stop and restart the port from software.
#
# authorizing=0 is a real disconnect from the device's point of view (the host
# trances the port), and =1 re-enumerates it. This script does exactly one
# pass of that dance on the port the phone is on, nothing else.
#
# Scope: this file is the ONLY thing the sudoers rule should hand to root:
#   placeless ALL=(root) NOPASSWD: /home/placeless/dev/p20-root/tools/ane_usb_revive_root.sh
set -eu

# find the port that currently holds a 12d1 device
PORT=""
for d in /sys/bus/usb/devices/*; do
  [ -e "$d/idVendor" ] || continue
  if [ "$(cat "$d/idVendor" 2>/dev/null)" = "12d1" ]; then
    PORT=$(basename "$d")
    break
  fi
done

if [ -z "$PORT" ]; then
  echo "no 12d1 device on the bus"
  exit 2
fi

AUTH="/sys/bus/usb/devices/$PORT/authorized"
if [ ! -e "$AUTH" ]; then
  echo "no authorized file for $PORT"
  exit 2
fi

# if the device moved (e.g. the port number includes an interface suffix), trim
case "$PORT" in
  *:*) PORT="${PORT%%:*}"; AUTH="/sys/bus/usb/devices/$PORT/authorized" ;;
esac

echo "port=$PORT"
echo "before: authorized=$(cat "$AUTH" 2>/dev/null) vendor=$(cat /sys/bus/usb/devices/$PORT/idVendor 2>/dev/null)"

echo 0 > "$AUTH"
echo "unplugged (authorized=0); holding ${1:-6}s"
sleep "${1:-6}"
echo 1 > "$AUTH"
echo "replugged (authorized=1)"
sleep 2
echo "after: authorized=$(cat "$AUTH" 2>/dev/null) product=$(cat /sys/bus/usb/devices/$PORT/product 2>/dev/null)"
