#!/bin/bash
# Try the most flag-like field in the frp partition: the 4 bytes right after the
# PDB magic (0x24), currently 0.
#
# The format is confirmed: bytes 0x00..0x1F are SHA256 of the whole partition with
# those bytes zeroed. So we flip the field, recompute the digest, and write the
# whole 768 KB image back. The original is on the host, so this is reversible.
#
# Then: reboot to the bootloader and see whether "Necessary to unlock FRP" is gone.
set -u
cd /home/placeless/dev/p20-root
CODE=0123456789ABCDEF

python3 - <<'PY'
import hashlib
d = bytearray(open("firmware/partitions/frp.bin", "rb").read())
print(f"original 0x24 field: {bytes(d[0x24:0x28]).hex()}")
d[0x24:0x28] = (1).to_bytes(4, "little")
zeroed = bytearray(d)
zeroed[0x00:0x20] = b"\0" * 32
d[0x00:0x20] = hashlib.sha256(bytes(zeroed)).digest()
open("firmware/partitions/frp_flagged.bin", "wb").write(bytes(d))
print(f"patched  0x24 field: {bytes(d[0x24:0x28]).hex()}")
print(f"new digest: {bytes(d[0:32]).hex()[:32]}...")
# sanity: recompute
chk = bytearray(open("firmware/partitions/frp_flagged.bin", "rb").read())
chk[0x00:0x20] = b"\0" * 32
assert hashlib.sha256(bytes(chk)).digest() == bytes(d[0x00:0x20]), "digest self-check failed"
print("digest self-check: OK")
PY

echo
echo "############ device state"
timeout 20 fastboot devices 2>&1 | head -2
timeout 20 adb devices 2>&1 | head -2
if ! timeout 20 adb devices 2>/dev/null | grep -q "device$"; then
  echo "  not in Android; rebooting from fastboot"
  timeout 60 fastboot reboot 2>&1 | head -1
  for i in $(seq 1 24); do
    ST=$(timeout 15 adb devices 2>/dev/null | awk 'NR==2{print $2}')
    [ "$ST" = "device" ] && break
    sleep 5
  done
fi
timeout 20 adb devices 2>&1 | head -2

echo
echo "############ push the patched image and write it with root"
timeout 60 adb push firmware/partitions/frp_flagged.bin /data/local/tmp/frp_flagged.bin 2>&1 | tail -1
timeout 60 adb push firmware/partitions/frp.bin /data/local/tmp/frp_orig.bin 2>&1 | tail -1

cat > /tmp/wfrp.sh <<'INNER'
id
chmod 666 /data/local/tmp/frp_flagged.bin /data/local/tmp/frp_orig.bin
echo "=== writing patched frp ==="
dd if=/data/local/tmp/frp_flagged.bin of=/dev/block/bootdevice/by-name/frp bs=4096
echo "=== read back, first 96 bytes ==="
od -A x -t x1 -N 96 /dev/block/bootdevice/by-name/frp
echo "=== done ==="
exit
INNER
for attempt in 1 2 3 4 5; do
  OUT=$(timeout 240 adb shell /data/local/tmp/cve-2019-2215 < /tmp/wfrp.sh 2>&1 | tr -d '\000')
  echo "$OUT" | grep -aq "=== done ===" && { echo "$OUT" | grep -aE "writing|records|^0020|^0000|done" | head -10; break; }
  echo "  [attempt $attempt: no root shell]"; sleep 10
done

echo
echo "############ to the bootloader and try again"
timeout 60 adb reboot bootloader 2>&1 | head -1
for i in $(seq 1 20); do sleep 2; timeout 10 fastboot devices 2>/dev/null | grep -q . && break; done
timeout 20 fastboot devices 2>&1 | head -2
echo "--- before:"; timeout 60 fastboot oem lock-state info 2>&1 | head -3
echo "--- unlock:"; timeout 120 fastboot oem unlock $CODE 2>&1 | head -6
sleep 15
echo "--- after:"; timeout 60 fastboot oem lock-state info 2>&1 | head -3
