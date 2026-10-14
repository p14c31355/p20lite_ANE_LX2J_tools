#!/usr/bin/env python3
"""
List the partition images inside UPDATE.APP in write order.

Header layout, derived from the hexdump:
    magic   4   b"\\x55\\xaa\\x5a\\xa5"
    hdr_sz  4   total header length
    unk1    4
    hw_id   8
    seq     4
    size    4   payload length
    date   16
    time   16
    type   16   <- partition name
    blank1 16
    hdr_crc 2
    block_size 2
    blank2  2
    checksum   hdr_sz - 98
    payload   size bytes

The first block is type SHA256RSA (the chipset signature), the second is CRC.
Everything after that is what actually gets written to flash, in order.
"""
import struct
import zipfile

Z = "/tmp/fw3/Software/dload/update_sd.zip"
MAGIC = b"\x55\xaa\x5a\xa5"

with zipfile.ZipFile(Z) as z, z.open("UPDATE.APP") as f:
    data = f.read(6 * 1024 * 1024)     # headers and small blocks live up front

pos = data.find(MAGIC)
print(f"first magic at {pos:#x}\n")
n = 0
while pos != -1 and n < 60:
    if pos + 100 > len(data):
        break
    hdr_sz, unk1, hw_id, seq, size = struct.unpack("<IIQII", data[pos + 4:pos + 28])
    date = data[pos + 28:pos + 44].decode("ascii", "replace").strip("\x00")
    time = data[pos + 44:pos + 60].decode("ascii", "replace").strip("\x00")
    ptype = data[pos + 60:pos + 76].decode("ascii", "replace").strip("\x00")
    if not (50 <= hdr_sz <= 4096) or size > 5_000_000_000:
        print(f"  implausible at {pos:#x}: hdr_sz={hdr_sz} size={size} type={ptype!r}")
        break
    print(f"  [{n:>2}] @{pos:#010x}  {ptype:<14} hdr={hdr_sz:<4} "
          f"payload={size:>12,}  {date} {time}  hw_id={hw_id:#018x} seq={seq:#x}")
    n += 1
    nxt = pos + hdr_sz + size
    pos = data.find(MAGIC, nxt)
    if pos == -1:
        # beyond our 6 MB window: report what the next header would be
        print(f"\n  (next header would be at {nxt:#x}, past the {len(data):,}-byte window)")
        break

print(f"\n  blocks listed: {n}")
