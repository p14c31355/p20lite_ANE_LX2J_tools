#!/usr/bin/env python3
"""List UPDATE.APP's blocks and extract KERNEL, with correct chunk-boundary handling.

UPDATE.APP is 4.3 GB decompressed and the zip member is not seekable, so this
streams it once with a small state machine:

    scan     - look for the block magic, parse the header, record the block
    skip     - consume the rest of a payload we do not want
    capture  - write the rest of the payload we do want

The first version got this wrong: it jumped the scan index past a payload that
extended beyond the current chunk, which corrupted the absolute position and hid
every block after the last small one.
"""
import os
import struct
import zipfile

Z = "/home/placeless/dev/p20-root/firmware/samesize/update_sd.zip"
OUT = "/tmp/kern"
MAGIC = b"\x55\xaa\x5a\xa5"
CHUNK = 1 << 20
WANT = ("KERNEL", "RAMDISK")

os.makedirs(OUT, exist_ok=True)

blocks = []
pos = 0                    # absolute offset of buf[0]
carry = b""                # bytes not yet consumed
state = "scan"
remaining = 0              # bytes left in the current skip/capture
fh = None
cur = None


def flush_capture():
    global fh, cur
    if fh:
        fh.close()
        print(f"  wrote {OUT}/{cur.lower()}.img "
              f"({os.path.getsize(f'{OUT}/{cur.lower()}.img'):,} bytes)")
    fh, cur = None, None


with zipfile.ZipFile(Z) as z, z.open("UPDATE.APP") as f:
    while True:
        chunk = f.read(CHUNK)
        if not chunk:
            break
        buf = carry + chunk
        i = 0

        while i < len(buf):
            if state != "scan":
                take = min(remaining, len(buf) - i)
                if state == "capture":
                    fh.write(buf[i:i+take])
                i += take
                remaining -= take
                if remaining == 0:
                    if state == "capture":
                        flush_capture()
                    state = "scan"
                continue

            # scanning for a header
            j = buf.find(MAGIC, i)
            if j == -1 or j + 100 > len(buf):
                # keep a possible partial magic for the next round
                i = max(i, len(buf) - 3)
                break
            hdr_sz, unk1, hw_id, seq, size = struct.unpack("<IIQII", buf[j+4:j+28])
            ptype = buf[j+60:j+76].decode("ascii", "replace").strip("\x00")
            if not (50 <= hdr_sz <= 4096) or size > 5_000_000_000:
                i = j + 1
                continue

            print(f"[{len(blocks):>2}] @{pos+j:#012x} {ptype:<16} hdr={hdr_sz:<4} "
                  f"payload={size:>12,}")
            blocks.append((len(blocks), ptype, pos + j, hdr_sz, size))
            i = j + hdr_sz

            if ptype in WANT:
                cur = ptype
                fh = open(f"{OUT}/{ptype.lower()}.img", "wb")
                state = "capture"
            else:
                state = "skip"
            remaining = size
            if remaining == 0:
                if state == "capture":
                    flush_capture()
                state = "scan"

        carry = buf[i:]
        pos += i

print(f"\nblocks: {len(blocks)}")
print("names:", sorted({b[1] for b in blocks}))
print("extracted:", sorted(os.listdir(OUT)))
