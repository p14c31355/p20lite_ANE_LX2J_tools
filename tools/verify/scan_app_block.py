#!/usr/bin/env python3
"""Extract one named block from a Huawei UPDATE.APP.

Same header walk as scan_app_all.py: 4-byte magic 0x55aa5aa5, then
hdr_sz/unk/hw_id/seq/size at +4..28 (little-endian), and the block type as
ASCII at +60..76. Extracting a named block (VENDOR, SYSTEM, ...) is how we
read partition contents without the phone - e.g. the vendor image's
init.chip.usb.rc, which decides how the USB default is set.

Usage: scan_app_block.py <UPDATE.APP> <TYPE> [out.img]
"""
import os
import struct
import sys

MAGIC = b"\x55\xaa\x5a\xa5"


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    app, want = sys.argv[1], sys.argv[2].upper()
    out = sys.argv[3] if len(sys.argv) > 3 else f"/tmp/{want.lower()}.img"

    data = open(app, "rb").read()
    print(f"file: {len(data):,} bytes; looking for {want}")
    pos = 0
    found = []
    while True:
        j = data.find(MAGIC, pos)
        if j == -1:
            break
        if j + 100 <= len(data):
            hdr_sz, _unk, _hw, _seq, size = struct.unpack("<IIQII", data[j + 4:j + 28])
            ptype = data[j + 60:j + 76].decode("ascii", "replace").strip("\x00")
            if all(32 <= ord(c) < 127 for c in ptype) and 1 <= len(ptype) <= 16 \
               and 50 <= hdr_sz <= 65536 and size <= 5_000_000_000:
                found.append((j, hdr_sz, size, ptype))
                if ptype.upper() == want:
                    with open(out, "wb") as f:
                        f.write(data[j + hdr_sz:j + hdr_sz + size])
                    print(f"wrote {out} ({size:,} bytes, hdr={hdr_sz})")
                    return 0
        pos = j + 1
    print("blocks seen:", sorted({t for (_, _, _, t) in found}))
    print(f"!! no block named {want}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
