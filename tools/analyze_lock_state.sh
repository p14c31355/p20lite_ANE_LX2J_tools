#!/bin/bash
# Host-side analysis of what we just pulled: do the partitions carry any readable
# lock state, and what does Huawei's oeminfo library actually touch?
set -u
cd /home/placeless/dev/p20-root
P=firmware/partitions

echo "############ strings in the dumps (looking for lock markers)"
for f in frp misc oeminfo; do
  echo "== $f.bin ($(stat -c%s $P/$f.bin) bytes)"
  strings -n 5 "$P/$f.bin" | sort -u | head -20
  echo
done

echo "############ pull liboeminfo.so and look inside"
timeout 120 adb pull /vendor/lib64/liboeminfo.so firmware/liboeminfo.so 2>&1 | tail -1
echo "--- size:"; ls -la firmware/liboeminfo.so 2>/dev/null
echo "--- strings mentioning the relevant concepts:"
strings -n 4 firmware/liboeminfo.so 2>/dev/null | grep -iE "unlock|lock|frp|oeminfo|persist|misc|by-name|/dev|nvme|flag" | sort -u | head -30

echo
echo "############ where else does the oemlock logic live?"
timeout 60 adb shell 'find /system /vendor -iname "*oemlock*" 2>/dev/null | head -10' 2>&1
timeout 60 adb shell 'getprop | grep -iE "oem|unlock|frp" | head -10' 2>&1
