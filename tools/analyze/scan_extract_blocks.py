#!/usr/bin/env python3
"""Scan a Huawei UPDATE.APP (or an inner *.app) for block headers and pull out the
block(s) we want - normally KERNEL.

The header layout was established from the 8.0.0.110(C635) package and works for
the 2018-era ANE builds:

    0   magic   55 aa 5a a5        (4)
    4   hdr_sz  u32  header length in bytes (100 in this era)
    8   unk1    u32
    12  hw_id   u64
    20  seq     u32
    24  size    u32  payload length in bytes
    ...
    60  name    char[16], NUL padded

The payload follows the header and is `size` bytes long. The file is multi-GB and
not seekable when it comes straight out of a zip member, so this streams it once
with a small state machine (scan / skip / capture) instead of seeking.

The first version of this logic jumped past payloads that crossed a chunk
boundary, which corrupted the absolute position and hid every block after the
last small one - hence the state machine.
"""
import os
import struct
import sys

MAGIC = b"\x55\xaa\x5a\xa5"
CHUNK = 1 << 20


def scan(path, outdir, want):
    os.makedirs(outdir, exist_ok=True)
    blocks = []
    pos = 0
    carry = b""
    state = "scan"
    remaining = 0
    fh = None
    cur = None

    def flush_capture():
        nonlocal fh, cur
        if fh:
            fh.close()
            dest = os.path.join(outdir, f"{cur.lower()}.img")
            print(f"  wrote {dest} ({os.path.getsize(dest):,} bytes)")
        fh, cur = None, None

    with open(path, "rb") as f:
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
                        fh.write(buf[i:i + take])
                    i += take
                    remaining -= take
                    if remaining == 0:
                        if state == "capture":
                            flush_capture()
                        state = "scan"
                    continue

                j = buf.find(MAGIC, i)
                if j == -1 or j + 100 > len(buf):
                    i = max(i, len(buf) - 3)
                    break
                hdr_sz, _unk1, _hw_id, _seq, size = struct.unpack("<IIQII", buf[j + 4:j + 28])
                ptype = buf[j + 60:j + 76].decode("ascii", "replace").strip("\x00")
                if not (50 <= hdr_sz <= 65536) or size > 5_000_000_000:
                    i = j + 1
                    continue

                print(f"[{len(blocks):>2}] @{pos + j:#012x} {ptype:<16} hdr={hdr_sz:<4} "
                      f"payload={size:>12,}")
                blocks.append((ptype, pos + j, hdr_sz, size))
                i = j + hdr_sz

                if ptype in want:
                    cur = ptype
                    fh = open(os.path.join(outdir, f"{ptype.lower()}.img"), "wb")
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
    print("names:", sorted({b[0] for b in blocks}))
    return blocks


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(f"usage: {sys.argv[0]} <UPDATE.APP|*.app> <outdir> [want1,want2]")
    app, outdir = sys.argv[1], sys.argv[2]
    want = tuple(sys.argv[3].split(",")) if len(sys.argv) > 3 else ("KERNEL",)
    print(f"scanning {app} ({os.path.getsize(app):,} bytes), want={want}")
    scan(app, outdir, want)
