#!/usr/bin/env bash
# After the RESTORE fire: wait for Android, take root (one shot), dump reserved RAM.
#
# Why: the blackbox record ring never arms on the ANE-LX2J (there is no
# ramoops_meta_region in its device tree - confirmed against firmware/ane_dtb),
# so nothing the probes write can be read back by a later boot.  What does
# survive is the raw data itself: the bare-metal probes' trace slots sit in
# reserved RAM (pstore-mem @0x34800000, no-map) and stay put until the next
# probe boot.  With root on the stock Android, adb can dump that RAM directly -
# no display, no camera, no assumptions about which region survives.
#
# The dump range: 0x34000000..0x34900000 (9 MiB) covers bbox-mem (Huawei's own
# blackbox buffer) plus pstore-mem (our trace slot 0x348c0000 and the step-mark
# block 0x348df000).
set -u
cd "$(dirname "$0")"
LOG=usb_runs/root_dump.log
say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }

say "waiting for an adb device (the RESTORE fire should bring Android)"
for i in $(seq 1 400); do
  if timeout 8 adb devices 2>/dev/null | grep -q "device$"; then break; fi
  sleep 5
done
if ! timeout 8 adb devices 2>/dev/null | grep -q "device$"; then
  say "no adb device appeared within ~7.5 min"
  exit 1
fi
say "adb device present; settling 75 s (clean heap for the exploit, as measured before)"
sleep 75

say "pushing the exploit"
timeout 60 adb push working/cve-2019-2215_0x134c838 /data/local/tmp/cve-2019-2215 >/dev/null 2>&1 || true
timeout 30 adb shell chmod 755 /data/local/tmp/cve-2019-2215
md5=$(timeout 20 adb shell md5sum /data/local/tmp/cve-2019-2215 2>/dev/null | awk '{print $1}')
say "on-device exploit md5: $md5 (want f42b6fad4f1aa3a612494ce592b359b2)"

say "running the exploit with a dump script on stdin"
{
  echo 'id'
  echo 'dd if=/dev/mem of=/data/local/tmp/ram_34.bin bs=4096 skip=212992 count=2304 2>/tmp/dd.err; cat /tmp/dd.err'
  echo 'ls -la /data/local/tmp/ram_34.bin'
  echo 'sync'
} | timeout 180 adb shell /data/local/tmp/cve-2019-2215 > usb_runs/root_dump.out 2>&1 || true
say "root shell exited"
grep -a "uid=0" usb_runs/root_dump.out | head -2
timeout 240 adb pull /data/local/tmp/ram_34.bin usb_runs/ram_34.bin 2>&1 | tail -1
ls -la usb_runs/ram_34.bin 2>/dev/null || say "no dump landed"
say "done"
