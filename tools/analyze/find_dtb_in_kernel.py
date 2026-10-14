#!/usr/bin/env python3
"""Look for device trees inside the stock kernel image.

Huawei supplies the DTB from the separate `dts` partition, so this may find
nothing - but a compressed kernel frequently still carries one, and a real FDT
would give us the memory map and the hardware nodes for the port.
"""
import gzip
import struct

PATH = "firmware/kernel_stock.bin"
FDT_MAGIC = b"\xd0\x0d\xfe\xed"

d = open(PATH, "rb").read()
print(f"{PATH}: {len(d):,} bytes")
print(f"  first 8: {d[:8]!r}")

# the payload starts one 2048-byte page in
body = d[0x800:]
gzip_off = body.find(b"\x1f\x8b")
print(f"  gzip stream at payload+0x{gzip_off:x}" if gzip_off >= 0 else "  no gzip stream found")
if gzip_off >= 0:
    try:
        u = gzip.decompress(body[gzip_off:])
        open("firmware/kernel_stock_dec.bin", "wb").write(u)
        print(f"  decompressed: {len(u):,} bytes -> firmware/kernel_stock_dec.bin")
        print(f"  arm64 Image magic at 0x38: {u[0x38:0x3c]!r}")
        n = 0
        i = 0
        while True:
            j = u.find(FDT_MAGIC, i)
            if j == -1:
                break
            n += 1
            tot, = struct.unpack_from(">I", u, j + 4)
            print(f"    FDT candidate at 0x{j:x}: totalsize={tot:,}")
            i = j + 4
        print(f"  FDT magic occurrences: {n}")
        # hardware names, which are useful even without a parseable FDT
        for w in (b"hisi", b"dwc3", b"hi6", b"uart", b"pl011", b"dsi", b"panel",
                  b"simple-framebuffer", b"memory@", b"pmic"):
            c = u.count(w)
            if c:
                print(f"    {w.decode():20} {c}")
    except Exception as e:
        print(f"  decompress failed: {e}")
