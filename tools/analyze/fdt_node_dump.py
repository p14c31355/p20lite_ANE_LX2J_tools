#!/usr/bin/env python3
"""Dump one node's properties from the ANE device tree (dwmmc2 = eMMC)."""
import struct

blob = open("firmware/ane_dtb/fdt.dtb", "rb").read()
off_struct, off_strings = struct.unpack_from(">II", blob, 8)
size_strings, = struct.unpack_from(">I", blob, 32)


def cstr(b, o):
    e = b.index(b"\0", o)
    return b[o:e].decode("utf-8", "replace")


p = off_struct
path = []
want = False
while True:
    tag, = struct.unpack_from(">I", blob, p)
    p += 4
    if tag == 1:  # BEGIN_NODE
        name = cstr(blob, p)
        p += (len(name) + 4) // 4 * 4
        path.append(name)
        cur = "/".join(path)
        if "dwmmc2" in name or "ff37d000" in name:
            want = True
            print("=== NODE: %s ===" % cur)
        else:
            want = False
    elif tag == 2:
        path.pop()
        want = False
    elif tag == 3:
        plen, noff = struct.unpack_from(">II", blob, p)
        p += 8
        pname = cstr(blob, off_strings + noff)
        val = blob[p:p + plen]
        if want:
            if plen and plen <= 40:
                print("  %s = %s" % (pname, val.hex()))
            else:
                print("  %s = (%d bytes)" % (pname, plen))
        p += (plen + 3) // 4 * 4
    elif tag == 9:
        break
