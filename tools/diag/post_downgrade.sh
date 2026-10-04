#!/bin/bash
# POST-DOWNGRADE PLAYBOOK - do NOT run while the device is on EMUI 9.1.
#
# The exploit (willboka's CVE-2019-2215 port) is written against kernel 4.4.23
# with the P20 Lite's struct offsets. On the current 4.9.148 it would fail at best
# and destabilise the device at worst. Gate on /proc/version first.
#
# Stage 1 is READ-ONLY: dump oeminfo and inspect the bootloader-lock flag and the
# unlock code before anything is written to it.
set -u

echo "############ STAGE 0 - is the downgrade actually in place?"
K=$(timeout 30 adb shell 'cat /proc/version' 2>&1)
echo "kernel: $K"
timeout 30 adb shell 'getprop ro.build.display.id; getprop ro.build.version.release' 2>&1
case "$K" in
  *4.4.23*) echo ">>> kernel 4.4.23 confirmed - the exploit can be used" ;;
  *) echo ">>> NOT 4.4.23 - the exploit must not be run. Stopping."; exit 1 ;;
esac

echo
echo "############ STAGE 1 - run the exploit (opens a root shell on success)"
echo "The exploit prints its progress then hands over /system/bin/sh -p."
echo "Piping commands in is the simplest way to drive it."
timeout 300 adb shell '
  echo "id"; echo "uname -a"; echo "getenforce"
' >/dev/null 2>&1

# The exploit itself: uncomment when the kernel gate above passes.
#   timeout 600 adb shell "/data/local/tmp/cve-2019-2215 <<'EOS'
#   id
#   getprop ro.boot.flash.locked
#   EOS"

echo
echo "############ STAGE 2 - read-only: dump oeminfo and look at the lock flag"
echo "(oeminfo is /dev/block/mmcblk0p8 on this device, symlinked at by-name/oeminfo)"
echo "From a root shell, the safe first move is a dump, not a write:"
cat <<'EOS'
    dd if=/dev/block/by-name/oeminfo of=/data/local/tmp/oeminfo.img bs=4096
    ls -l /data/local/tmp/oeminfo.img
    adb pull /data/local/tmp/oeminfo.img      # then analyse on the host
EOS

echo
echo "############ STAGE 3 - the actual unlock (NOT yet scripted)"
cat <<'EOS'
Two candidate levers, both needing root, in order of preference:

  a) fastboot again: with the lock state perhaps more permissive on EMUI 8,
     retry the verbs that were refused on 9.1:
         fastboot oem unlock <code>
         fastboot oem oeminforead-SYSTEM_VERSION / -CUSTOM_VERSION
         (and check whether flash/boot are still refused)

  b) write the lock flag in oeminfo using the known offset once the dump
     has been analysed. The C# tool's route was an NV write of the FBLOCK
     item (getvar:nve:FBLOCK@0x01) - the oeminfo partition holds the same
     state.

Do not write oeminfo until the dump shows exactly which bytes carry the flag.
A wrong write there is the one failure mode that bricks this device.
EOS
