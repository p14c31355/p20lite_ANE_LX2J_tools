#!/bin/bash
# Write the unlock key straight into the nvme image, bypassing hisi-nve.
#
# The tool's own write did not land (the value in the partition is still the factory
# one), even though it reported "Hashing USRKEY...". We know the layout from its
# source: NV_NAME_LENGTH = 8, and the value field starts at name + 20. There are 7
# copies, spaced exactly 0x20000 apart.
#
# So: take the dump we just pulled, put SHA256("0123456789ABCDEF") into all 7 value
# fields, write the image back with dd, verify by re-reading, then unlock.
set -u
cd /home/placeless/dev/p20-root
CODE=0123456789ABCDEF

python3 - <<'PY'
import hashlib
src = "firmware/nvme_now.bin"
dst = "firmware/nvme_usrkey.bin"
d = bytearray(open(src, "rb").read())
code = b"0123456789ABCDEF"
h = hashlib.sha256(code).digest()
print(f"writing SHA256({code.decode()}) = {h.hex()}")
print()
n = 0
i = 0
while True:
    j = d.find(b"USRKEY", i)
    if j == -1:
        break
    off = j + 20                     # name(8) + 12, as the tool's source says
    before = bytes(d[off:off+32])
    d[off:off+32] = h
    n += 1
    print(f"  copy @0x{j:06x}: {before.hex()[:24]}... -> {h.hex()[:24]}...")
    i = j + 1
print(f"\ncopies patched: {n}")
open(dst, "wb").write(bytes(d))
print(f"wrote {dst} ({len(d):,} bytes)")
PY

echo
echo "############ push and write with root"
timeout 120 adb push firmware/nvme_usrkey.bin /data/local/tmp/nvme_usrkey.bin 2>&1 | tail -1

cat > /tmp/wnvme.sh <<'INNER'
id
chmod 666 /data/local/tmp/nvme_usrkey.bin
echo "=== writing nvme ==="
dd if=/data/local/tmp/nvme_usrkey.bin of=/dev/block/bootdevice/by-name/nvme bs=4096
sync
echo "=== read back the USRKEY value ==="
dd if=/dev/block/bootdevice/by-name/nvme of=/data/local/tmp/nvme_check.bin bs=4096 2>/dev/null
chmod 666 /data/local/tmp/nvme_check.bin
echo "=== done ==="
exit
INNER

for attempt in 1 2 3 4 5 6; do
  OUT=$(timeout 240 adb shell /data/local/tmp/cve-2019-2215 < /tmp/wnvme.sh 2>&1 | tr -d '\000')
  echo "$OUT" | grep -aq "=== done ===" && { echo "$OUT" | grep -aE "records|done" | head -5; break; }
  echo "  [attempt $attempt: no root shell]"
done

echo
echo "############ pull back and verify"
timeout 120 adb pull /data/local/tmp/nvme_check.bin firmware/nvme_check.bin 2>&1 | tail -1
python3 - <<'PY'
import hashlib
want = hashlib.sha256(b"0123456789ABCDEF").digest()
for f in ("firmware/nvme_usrkey.bin", "firmware/nvme_check.bin"):
    try:
        d = open(f, "rb").read()
    except FileNotFoundError:
        print(f"{f}: missing"); continue
    ok = 0; bad = 0
    i = 0
    while True:
        j = d.find(b"USRKEY", i)
        if j == -1: break
        val = d[j+20:j+20+32]
        if val == want: ok += 1
        else: bad += 1
        i = j + 1
    print(f"{f}: {ok} copies correct, {bad} still different")
PY
