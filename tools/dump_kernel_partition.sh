#!/bin/bash
# Pull the kernel partition off the device (we have root) and inspect the format,
# which tells us what the LK will accept - and whether Fullerene's arm64 Image
# would fit that contract.
set -u
cd /home/placeless/dev/p20-root

cat > /tmp/kdump.sh <<'INNER'
id
echo "=== kernel partition ==="
ls -la /dev/block/bootdevice/by-name/kernel
dd if=/dev/block/bootdevice/by-name/kernel of=/data/local/tmp/kernel_stock.bin bs=4096 2>&1 | tail -1
chmod 666 /data/local/tmp/kernel_stock.bin
echo "=== dts partition (the device tree the LK passes) ==="
ls -la /dev/block/bootdevice/by-name/dts
dd if=/dev/block/bootdevice/by-name/dts of=/data/local/tmp/dts_stock.bin bs=4096 2>&1 | tail -1
chmod 666 /data/local/tmp/dts_stock.bin
echo "=== cmdline / bootargs the LK supplies ==="
cat /proc/cmdline
echo "=== done ==="
exit
INNER

for attempt in 1 2 3 4 5 6; do
  OUT=$(timeout 240 adb shell /data/local/tmp/cve-2019-2215 < /tmp/kdump.sh 2>&1 | tr -d '\000')
  echo "$OUT" | grep -aq "=== done ===" && { echo "$OUT" | grep -aE "records|kernel|dts|cmdline|done|uid=0" | head -12; break; }
  echo "  [attempt $attempt: no root shell]"
done

echo
timeout 180 adb pull /data/local/tmp/kernel_stock.bin firmware/kernel_stock.bin 2>&1 | tail -1
timeout 180 adb pull /data/local/tmp/dts_stock.bin firmware/dts_stock.bin 2>&1 | tail -1
ls -la firmware/kernel_stock.bin firmware/dts_stock.bin 2>/dev/null

echo
echo "############ STOCK FORMAT (what the LK boots today)"
python3 probe_kernel_format.py firmware/kernel_stock.bin kernels/110/kernel.img

echo
echo "############ Fullerene's aarch64 image format, for comparison"
python3 probe_kernel_format.py /home/placeless/dev/fullerene/alc286.txt 2>/dev/null | head -3
grep -rn "ARM64_IMAGE_MAGIC\|AARCH64_IMAGE_TEXT_OFFSET" /home/placeless/dev/fullerene/flasks/src/main.rs | head -4
