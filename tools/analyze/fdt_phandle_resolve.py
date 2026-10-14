#!/usr/bin/env python3
"""Resolve phandles -> full path + all props for the SD clock chain."""
import struct

blob = open("firmware/ane_dtb/fdt.dtb", "rb").read()
off_struct, off_strings = struct.unpack_from(">II", blob, 8)


def cstr(b, o):
    e = b.index(b"\0", o)
    return b[o:e].decode("utf-8", "replace")


WANT = {0x1A4, 0x1A5, 0x157, 0x158, 0x159, 0x15A, 0x153, 0x107,
        0x142, 0x141, 0x13C, 0x13A, 0x10C, 0x13B, 0x14E, 0x152, 0x154, 0x155, 0x156, 0x15B, 0x15C}

p = off_struct
path = []
while True:
    tag, = struct.unpack_from(">I", blob, p)
    p += 4
    if tag == 1:
        name = cstr(blob, p)
        p += (len(name) + 4) // 4 * 4
        path.append(name)
        save = p
        ph = None
        props = []
        depth = 0
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
                if pname == "phandle" and plen >= 4:
                    ph = struct.unpack(">I", val[:4])[0]
                props.append((pname, val.hex() if plen <= 32 else "len%d" % plen))
                p += (plen + 3) // 4 * 4
            elif t2 == 1:
                cn = cstr(blob, p)
                p += (len(cn) + 4) // 4 * 4
                depth += 1
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
            else:
                break
        if ph in WANT:
            print("### 0x%03x %s" % (ph, "/".join(path)))
            for pname, val in props:
                print("      %s = %s" % (pname, val))
        p = save
    elif tag == 2:
        path.pop()
    elif tag == 3:
        plen, noff = struct.unpack_from(">II", blob, p)
        p += 8
        p += (plen + 3) // 4 * 4
    elif tag == 9:
        break
