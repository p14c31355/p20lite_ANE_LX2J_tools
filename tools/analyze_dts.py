#!/usr/bin/env python3
"""What is actually inside the ANE-LX2J dts partition?

29,360,128 bytes is far too big for one device tree, so it is probably a bundle
and/or compressed. Look for FDT magic (d00dfeed), gzip/lz4 wrappers, and any
readable strings that name the hardware we need to drive.
"""
import gzip
import struct
import sys

PATH = "firmware/dts_stock.bin"
FDT_MAGIC = b"\xd0\x0d\xfe\xed"


def main():
    d = open(PATH, "rb").read()
    print(f"{PATH}: {len(d):,} bytes")
    print(f"  first 32 bytes: {d[:32].hex()}")

    # container detection
    if d[:2] == b"\x1f\x8b":
        print("  gzip container -> decompressing")
        d = gzip.decompress(d)
        print(f"  decompressed: {len(d):,} bytes, first 16 = {d[:16].hex()}")

    # how many FDTs?
    offs = []
    i = 0
    while True:
        j = d.find(FDT_MAGIC, i)
        if j == -1:
            break
        offs.append(j)
        i = j + 4
    print(f"  FDT magic occurrences: {len(offs)}")
    for o in offs[:10]:
        tot = struct.unpack_from(">I", d, o + 4)[0] if o + 8 <= len(d) else 0
        print(f"    at 0x{o:08x}: totalsize={tot:,}")

    # strings that name hardware
    if len(d) > 1_000_000:
        window = d[:4_000_000]
        print("  (scanning the first 4 MB for hardware names)")
    else:
        window = d
    interesting = [b"hisi", b"dwc3", b"usb", b"uart", b"pl011", b"kirin", b"hi6",
                   b"display", b"mipi", b"dsi", b"panel", b"pmic", b"hi6421",
                   b"framebuffer", b"simple-framebuffer", b"memory@", b"chosen"]
    for word in interesting:
        n = window.count(word)
        if n:
            print(f"    {word.decode():20} {n} occurrences")


if __name__ == "__main__":
    main()
