#!/bin/bash
# Per-boot host-side forensic snapshot: the /sys descriptor blob the host
# kernel read, plus the parsed fields. Run after each new device appears.
cd "$HOME/dev/p20-root" || exit 1
mkdir -p forensics
D=/sys/bus/usb/devices/1-1
TS=$(date +%H%M%S)
OUT="forensics/snap_${TS}"
{
  echo "time: $(date '+%F %T')"
  for f in idVendor idProduct bcdDevice bDeviceClass bMaxPacketSize0 \
           bNumConfigurations bConfigurationValue bNumInterfaces \
           manufacturer product serial speed version; do
    printf "%-20s %s\n" "$f:" "$(cat "$D/$f" 2>/dev/null)"
  done
} > "${OUT}.txt"
cp "$D/descriptors" "${OUT}.bin" 2>/dev/null
echo "== snapshot ${OUT}"
cat "${OUT}.txt"
SIZE=$(stat -c %s "${OUT}.bin" 2>/dev/null || echo 0)
echo "descriptors: ${SIZE} bytes"
xxd "${OUT}.bin" | head -8
