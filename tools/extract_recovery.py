#!/usr/bin/env python3
"""
Extract the RECOVERY_RAMDISK image from our own UPDATE.APP and dig out the
recovery binary's strings.

Why: the pre-checks that stop the update at ~5% live in the recovery binary, not
in update-binary (verified: update-binary's strings mention only SD_update.tag and
full_mainpkg.tag). Our package carries a RECOVERY_RAMDISK block for the same ANNE
device family, so its check code will name the files and formats that are being
looked for.

Block map (from list_update_app3):
   [16] RECOVERY_RAMDISK  @0x4651390  hdr=16482  size=33,554,432
   [17] RECOVERY_VENDOR   @0x66553f4  hdr=8290   size=16,777,216
"""
import gzip
import io
import re
import struct
import zipfile

Z = "/tmp/fw3/Software/dload/update_sd.zip"
OUT = "/tmp/recov"
import os
os.makedirs(OUT, exist_ok=True)

BLOCK_OFFSET = 0x4651390
BLOCK_HDR = 16482
BLOCK_SIZE = 33_554_432

with zipfile.ZipFile(Z) as z, z.open("UPDATE.APP") as f:
    f.seek(BLOCK_OFFSET)
    img = f.read(BLOCK_HDR + BLOCK_SIZE)
data = img[BLOCK_HDR:BLOCK_HDR + BLOCK_SIZE]
print(f"recovery image: {len(data):,} bytes")
open(f"{OUT}/recovery_ramdisk.img", "wb").write(data)

print("\n=== image header ===")
print("  first 64 bytes:", data[:64])
hdr = data[:64].hex()
print(f"  hex: {hdr}")

# Android boot image magic is "ANDROID!"
if data[:8] == b"ANDROID!":
    print("  -> Android boot image")
    # header v0: magic[8] then NINE u32 (kernel_size, kernel_addr, ramdisk_size,
    # ramdisk_addr, second_size, second_addr, tags_addr, page_size, os_version)
    (magic, kernel_size, kernel_addr, ramdisk_size, ramdisk_addr, second_size,
     second_addr, tags_addr, page_size, os_version, name, cmdline, img_id) = \
        struct.unpack("<8sIIIIIIIII16s512s32s", data[:604])
    print(f"     kernel={kernel_size:,} ramdisk={ramdisk_size:,} page={page_size}")
    off = page_size
    ker = data[off:off + kernel_size]
    off += (kernel_size + page_size - 1) // page_size * page_size
    rd = data[off:off + ramdisk_size]
    print(f"     ramdisk bytes: {len(rd):,}; first 8: {rd[:8]}")
    open(f"{OUT}/recovery_ramdisk.gz", "wb").write(rd)
    payload = rd
else:
    # maybe a pure ramdisk or a Hisilicon header; look for gzip magic
    i = data.find(b"\x1f\x8b\x08")
    print(f"  -> gzip magic at {i:#x}")
    payload = data[i:] if i != -1 else data
    open(f"{OUT}/recovery_ramdisk.gz", "wb").write(payload)

print("\n=== unpack ramdisk (gzip + cpio) ===")
try:
    raw = gzip.decompress(payload)
except Exception as e:
    print("  gzip failed:", e)
    raise SystemExit(1)
print(f"  uncompressed ramdisk: {len(raw):,} bytes")
open(f"{OUT}/recovery_ramdisk.cpio", "wb").write(raw)

# walk the newc cpio to list file names
names = []
p = 0
while p + 110 <= len(raw):
    if raw[p:p + 6] not in (b"070701", b"070702"):
        nxt = raw.find(b"070701", p)
        if nxt == -1:
            break
        p = nxt
    try:
        (magic, ino, mode, uid, gid, nlink, mtime, filesize, devmajor, devminor,
         rdevmajor, rdevminor, namesize, check) = struct.unpack("<6sIIIIIIIIIIIIII", raw[p:p + 110])
    except struct.error:
        break
    name = raw[p + 110:p + 110 + namesize - 1].decode("utf-8", "replace")
    names.append((name, filesize))
    body = p + 110 + namesize
    body += (-body) % 4
    body += filesize
    body += (-body) % 4
    p = body
    if name == "TRAILER!!!":
        break
print(f"  files in ramdisk: {len(names)}")
interesting = [n for n, _ in names if re.search(r"recovery|sbin|bin/|init", n)]
for n in interesting[:40]:
    print("   ", n)

# find the recovery binary and dump its strings
target = [n for n, s in names if n.endswith("sbin/recovery") or n.endswith("/recovery")]
print("\n  candidate recovery binaries:", target)
