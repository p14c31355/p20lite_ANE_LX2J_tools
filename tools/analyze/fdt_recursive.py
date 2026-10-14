#!/usr/bin/env python3
"""Careful recursive FDT walk. Prints /clocks@0 depth-2 containers with regs,
and the full ancestor chain (with reg props) of the clk_sd / clk_mmc1_div nodes."""
import struct

blob = open("firmware/ane_dtb/fdt.dtb", "rb").read()
off_struct, off_strings = struct.unpack_from(">II", blob, 8)


def cstr(b, o):
    e = b.index(b"\0", o)
    return b[o:e].decode("utf-8", "replace")


records = []  # (path_tuple, props dict)


def walk(p, path):
    while True:
        tag, = struct.unpack_from(">I", blob, p)
        p += 4
        if tag == 1:
            name = cstr(blob, p)
            p += (len(name) + 4) // 4 * 4
            p = walk(p, path + [name])
        elif tag == 2:
            return p
        elif tag == 3:
            plen, noff = struct.unpack_from(">II", blob, p)
            p += 8
            pname = cstr(blob, off_strings + noff)
            val = blob[p:p + plen]
            if path:
                records.append((tuple(path), pname, val))
            p += (plen + 3) // 4 * 4
        elif tag == 4:
            pass
        elif tag == 9:
            return p


walk(off_struct, [])

# collapse into node -> props
nodes = {}
for pt, pname, val in records:
    nodes.setdefault(pt, {})[pname] = val

print("=== /clocks@0 containers (depth<=4) with reg ===")
for pt, props in sorted(nodes.items()):
    if len(pt) >= 2 and pt[0] == "clocks@0" and "reg" in props:
        reg = props["reg"].hex()
        comp = props.get("compatible", b"").decode("utf-8", "replace").rstrip("\0")
        st = props.get("status", b"ok").decode("utf-8", "replace").rstrip("\0")
        print("  /%s  reg=%s compatible=%s status=%s" % ("/".join(pt), reg, comp, st))

print("=== ancestor chain of nodes named clk_sd / clk_mmc1_div / hclk_sd ===")
for pt, props in sorted(nodes.items()):
    if pt and pt[-1] in ("clk_sd", "clk_mmc1_div", "hclk_sd", "clk_emmc0"):
        print("node /%s" % "/".join(pt))
        for i in range(1, len(pt) + 1):
            anc = pt[:i]
            aprops = nodes.get(anc, {})
            reg = aprops.get("reg", b"").hex()
            comp = aprops.get("compatible", b"").decode("utf-8", "replace").rstrip("\0")
            print("    anc /%s reg=%s compatible=%s" % ("/".join(anc), reg, comp))
        g = props.get("hisilicon,hi3xxx-clkgate", b"")
        print("    clkgate=%s" % g.hex())
