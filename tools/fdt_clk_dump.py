#!/usr/bin/env python3
"""Dump every clock node under the CRG and the dwmmc1 supply/clk links."""
import struct

blob = open("firmware/ane_dtb/fdt.dtb", "rb").read()
off_struct, off_strings = struct.unpack_from(">II", blob, 8)


def cstr(b, o):
    e = b.index(b"\0", o)
    return b[o:e].decode("utf-8", "replace")


p = off_struct
path = []
while True:
    tag, = struct.unpack_from(">I", blob, p)
    p += 4
    if tag == 1:
        name = cstr(blob, p)
        p += (len(name) + 4) // 4 * 4
        path.append(name)
        cur = "/".join(path)
        interesting = ("clk_mmc" in name or "mmc" in name.lower()
                        or "dwmmc" in name or "sdhci" in name)
        if interesting:
            print("### %s" % cur)
            # dump all props until END_NODE
            save = p
            while True:
                t2, = struct.unpack_from(">I", blob, p)
                p += 4
                if t2 == 2:
                    break
                if t2 == 3:
                    plen, noff = struct.unpack_from(">II", blob, p)
                    p += 8
                    pname = cstr(blob, off_strings + noff)
                    val = blob[p:p + plen]
                    if plen <= 48:
                        print("    %s = %s" % (pname, val.hex()))
                    else:
                        print("    %s = (%d bytes)" % (pname, plen))
                    p += (plen + 3) // 4 * 4
                elif t2 == 1:
                    # nested child; skip its name then its props recursively
                    cn = cstr(blob, p)
                    p += (len(cn) + 4) // 4 * 4
                    depth = 1
                    while depth:
                        t3, = struct.unpack_from(">I", blob, p)
                        p += 4
                        if t3 == 1:
                            cn = cstr(blob, p)
                            p += (len(cn) + 4) // 4 * 4
                            depth += 1
                        elif t3 == 2:
                            depth -= 1
                        elif t3 == 3:
                            plen, noff = struct.unpack_from(">II", blob, p)
                            p += 8
                            p += (plen + 3) // 4 * 4
                elif t2 == 4:
                    pass
                elif t2 == 9:
                    p = save
                    break
            path.pop()
    elif tag == 2:
        path.pop()
    elif tag == 3:
        plen, noff = struct.unpack_from(">II", blob, p)
        p += 8
        p += (plen + 3) // 4 * 4
    elif tag == 9:
        break
