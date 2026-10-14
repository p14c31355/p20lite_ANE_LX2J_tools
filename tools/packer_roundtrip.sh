#!/bin/bash
# Round-trip validation of the ANE boot-image packer.
#
# 1. Take the stock kernel image apart: header + gzip payload.
# 2. Decompress the payload to get the real arm64 Image.
# 3. Repack it with our own tool.
# 4. Flash the repack. If the device boots, the packer is proven correct - which is
#    the foundation everything else needs.
set -u
cd /home/placeless/dev/p20-root
W=firmware/ane_bootimg
mkdir -p "$W"

echo "############ 1. unpack the stock image"
python3 - <<'PY'
import gzip, struct
d = open("firmware/kernel_stock.bin", "rb").read()
ps, = struct.unpack_from("<I", d, 0x24)
ksz, = struct.unpack_from("<I", d, 0x08)
print(f"  page_size={ps} kernel_size={ksz:,}")
payload = d[ps:ps+ksz]
open("firmware/ane_bootimg/stock_payload.gz", "wb").write(payload)
u = gzip.decompress(payload)
open("firmware/ane_bootimg/stock_Image", "wb").write(u)
print(f"  payload  : {len(payload):,} bytes -> firmware/ane_bootimg/stock_payload.gz")
print(f"  Image    : {len(u):,} bytes -> firmware/ane_bootimg/stock_Image")
print(f"  Image magic at 0x38: {u[0x38:0x3c]!r}")
PY

echo
echo "############ 2. repack with our packer (gzip, stock cmdline)"
python3 mkane_bootimg.py firmware/ane_bootimg/stock_Image firmware/ane_bootimg/repacked_stock.img --gzip

echo
echo "############ 3. compare headers"
python3 - <<'PY'
import struct
a = open("firmware/kernel_stock.bin","rb").read()
b = open("firmware/ane_bootimg/repacked_stock.img","rb").read()
print(f"  stock   : {len(a):,} bytes")
print(f"  repacked: {len(b):,} bytes")
for name, off in (("magic",0),("kernel_size",8),("kernel_addr",12),("ramdisk_size",16),
                  ("tags_addr",0x20),("page_size",0x24),("os_version",0x2C)):
    if name == "magic":
        print(f"  {name:12} stock={a[:8]!r} repacked={b[:8]!r}")
    else:
        va, = struct.unpack_from("<I", a, off)
        vb, = struct.unpack_from("<I", b, off)
        same = "same" if va == vb else "DIFFERS"
        print(f"  {name:12} stock={va:#010x} repacked={vb:#010x}  {same}")
cmd_a = a[0x40:0x240].split(b"\0")[0]
cmd_b = b[0x40:0x240].split(b"\0")[0]
print(f"  cmdline identical: {cmd_a == cmd_b}")
PY

echo
echo "############ 4. flash the repack and see if it boots"
timeout 60 adb reboot bootloader 2>&1 | head -1
for i in $(seq 1 20); do sleep 2; timeout 8 fastboot devices 2>/dev/null | grep -q . && break; done
timeout 15 fastboot devices 2>&1 | head -2
timeout 300 fastboot flash kernel firmware/ane_bootimg/repacked_stock.img 2>&1 | tail -4
timeout 60 fastboot reboot 2>&1 | head -1
for i in $(seq 1 40); do
  ST=$(timeout 15 adb devices 2>/dev/null | awk 'NR==2{print $2}')
  [ "$ST" = "device" ] && { echo "  booted, adb back after $((i*5))s"; break; }
  sleep 5
done
echo
timeout 30 adb shell 'getprop ro.build.display.id; cat /proc/version' 2>&1 | head -3
