#!/bin/bash
# The bootloader now passes the USRKEY check and asks for two things:
#     Necessary to unlock FRP!
#     Navigate to Developer options, and enable "OEM unlock"!
# So: read what Android thinks those states are, set the oem_unlock_allowed flag
# with our root, and look at the frp partition (backing it up first).
set -u
cd /home/placeless/dev/p20-root

echo "############ back to Android"
timeout 60 fastboot reboot 2>&1 | head -1
sleep 30
for i in $(seq 1 30); do
  ST=$(timeout 20 adb devices 2>/dev/null | awk 'NR==2{print $2}')
  [ "$ST" = "device" ] && { echo "  adb: device"; break; }
  echo "  adb: ${ST:-none}"; sleep 10
done

echo
echo "############ what Android currently reports (no root needed)"
timeout 40 adb shell 'settings get global oem_unlock_allowed' 2>&1 | head -2
timeout 40 adb shell 'getprop ro.oem_unlock_supported; getprop ro.frp.pst; getprop ro.boot.flash.locked; getprop ro.secure' 2>&1 | head -5

echo
echo "############ with root: set the flag, inspect the frp partition"
timeout 300 adb shell /data/local/tmp/cve-2019-2215 <<'EOF' 2>&1 | tail -30
id
cat /proc/self/attr/current
echo "--- current setting:"
settings get global oem_unlock_allowed
echo "--- setting it:"
settings put global oem_unlock_allowed 1
settings get global oem_unlock_allowed
echo "--- frp partition (backup to /sdcard first)"
ls -la /dev/block/bootdevice/by-name/frp
dd if=/dev/block/bootdevice/by-name/frp of=/sdcard/frp_backup.bin bs=4096
ls -la /sdcard/frp_backup.bin
echo "--- frp contents (first 512 bytes):"
hexdump -C -n 512 /dev/block/bootdevice/by-name/frp 2>&1 | head -34
sync
exit
EOF

echo
echo "############ pull the frp backup for safekeeping"
timeout 60 adb pull /sdcard/frp_backup.bin /home/placeless/dev/p20-root/firmware/ 2>&1 | tail -1
