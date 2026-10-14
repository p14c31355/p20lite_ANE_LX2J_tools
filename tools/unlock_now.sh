#!/bin/bash
# The last step: once the exploit gives us root in a domain that can touch block
# devices, back up nvme, clear FBLOCK, and verify.
#
# Everything runs INSIDE the exploit's spawned root shell: its stdin is forwarded
# to the shell it creates, which is why the printf | adb shell construction is
# used instead of a plain adb shell.
#
# FBLOCK lives in the nvme partition (mmcblk0p7, 3 MB) and is a single byte:
#   0 = unlocked, 1 = locked
# hisi-nve opens the partition directly for it, so we need the SELinux bypass.
set -u
cd /home/placeless/dev/p20-root
NVME=/dev/block/bootdevice/by-name/nvme
STAMP=$(date +%Y%m%d_%H%M%S)
BACKUP=/sdcard/nvme_backup_$STAMP.bin

echo "############ 1. push the tools"
timeout 60 adb push /home/placeless/dev/hisi-nve/libs/arm64-v8a/hisi-nve /data/local/tmp/hisi-nve 2>&1 | tail -1
timeout 60 adb push /home/placeless/dev/p20lite-cve/libs/arm64-v8a/cve-2019-2215 /data/local/tmp/cve-2019-2215 2>&1 | tail -1
timeout 30 adb shell 'chmod 755 /data/local/tmp/hisi-nve /data/local/tmp/cve-2019-2215'

echo
echo "############ 2. exploit, then do everything inside the root shell"
timeout 300 adb shell /data/local/tmp/cve-2019-2215 <<EOF 2>&1 | tail -40
id
cat /proc/self/attr/current
echo "--- partition visible?"
ls -la $NVME
echo "--- backup (3 MB)"
dd if=$NVME of=$BACKUP bs=4096
echo "--- FBLOCK before"
/data/local/tmp/hisi-nve r FBLOCK
echo "--- FBLOCK write 0"
/data/local/tmp/hisi-nve w FBLOCK 0
echo "--- FBLOCK after"
/data/local/tmp/hisi-nve r FBLOCK
sync
echo "--- done"
exit
EOF

echo
echo "############ 3. verify the backup landed and pull it"
timeout 60 adb shell "ls -la $BACKUP" 2>&1 | tail -2
timeout 120 adb pull "$BACKUP" /home/placeless/dev/p20-root/firmware/ 2>&1 | tail -1
md5sum /home/placeless/dev/p20-root/firmware/*.bin 2>/dev/null | tail -2

echo
echo "############ 4. read the flag back outside the exploit"
timeout 30 adb shell "getprop ro.boot.flash.locked; getprop ro.secure; getprop ro.boot.verifiedbootstate" 2>&1
echo
echo "### next: reboot to the bootloader and read FB LockState"
echo "###   adb reboot bootloader; fastboot getvar ...   (or: fastboot oem device-info)"
