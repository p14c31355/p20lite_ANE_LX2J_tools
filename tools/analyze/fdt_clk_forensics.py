#!/usr/bin/env python3
"""Dump full path + ALL properties for selected clock nodes; list /clocks@0 children."""
import struct

blob = open("firmware/ane_dtb/fdt.dtb", "rb").read()
off_struct, off_strings = struct.unpack_from(">II", blob, 8)


def cstr(b, o):
    e = b.index(b"\0", o)
    return b[o:e].decode("utf-8", "replace")


TARGETS = ("clk_sd", "hclk_sd", "clkgt_mmc1", "clk_mmc1_div", "clk_sd_muxsys",
           "clk_sd_muxpll", "clk_factor_mmc0", "clk_sdio0", "clk_sdio0_muxsy")

p = off_struct
path = []
dump_all = True  # dump every node under /clocks@0 at depth<=2 with reg
while True:
    tag, = struct.unpack_from(">I", blob, p)
    p += 4
    if tag == 1:
        name = cstr(blob, p)
        p += (len(name) + 4) // 4 * 4
        path.append(name)
        cur = "/".join(path)
        interesting = any(name.startswith(t) for t in TARGETS) or name.startswith("crgctrl@") or name.startswith("sctrl@")
        if interesting:
            print("### %s" % cur)
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
                    if plen <= 48:
                        print("    %s = %s" % (pname, val.hex()))
                    else:
                        print("    %s = (%dB)" % (pname, plen))
                    p += (plen + 3) // 4 * 4
                elif t2 == 1:
                    cn = cstr(blob, p)
                    p += (len(cn) + 4) // 4 * 4
                    depth += 1
                    continue_flag = True
                    while depth:
                        t3, = struct.unpack_from(">I", blob, p)
                        p += 4
                        if t3 == 1:
                            cn2 = cstr(blob, p)
                            p += (len(cn2) + 4) // 4 * 4
                            depth += 1
                        elif t3 == 2:
                            depth -= 1
                        elif t3 == 3:
                            plen, noff = struct.unpack_from(">II", blob, p)
                            p += 8
                            p += (plen + 3) // 4 * 4
                elif t2 in (4,):
                    pass
                else:
                    break
    elif tag == 2:
        path.pop()
    elif tag == 3:
        plen, noff = struct.unpack_from(">II", blob, p)
        p += 8
        p += (plen + 3) // 4 * 4
    elif tag == 9:
        break
