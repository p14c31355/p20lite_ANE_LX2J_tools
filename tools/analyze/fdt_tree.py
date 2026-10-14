#!/usr/bin/env python3
"""Full-tree parse into memory, then answer targeted questions about
clk_sd / hclk_sd / clkgt nodes and their parent containers' regs."""
import struct

blob = open("firmware/ane_dtb/fdt.dtb", "rb").read()
off_struct, off_strings = struct.unpack_from(">II", blob, 8)


def cstr(b, o):
    e = b.index(b"\0", o)
    return b[o:e].decode("utf-8", "replace")


nodes = []  # (path, props dict name->bytes)
path = []
p = off_struct
while True:
    tag, = struct.unpack_from(">I", blob, p)
    p += 4
    if tag == 1:
        name = cstr(blob, p)
        p += (len(name) + 4) // 4 * 4
        path.append(name)
        props = {}
        while True:
            t2, = struct.unpack_from(">I", blob, p)
            p += 4
            if t2 == 2:
                break
            if t2 == 1:
                # unexpected nested begin: treat as sibling-ish; rewind by
                # pushing the name through the same loop (walk flat).
                cn = cstr(blob, p)
                p += (len(cn) + 4) // 4 * 4
                path.append(cn)
                continue
            if t2 == 3:
                plen, noff = struct.unpack_from(">II", blob, p)
                p += 8
                pname = cstr(blob, off_strings + noff)
                props[pname] = blob[p:p + plen]
                p += (plen + 3) // 4 * 4
            if t2 == 4:
                continue
            if t2 == 9:
                break
        nodes.append(("/".join(path), props))
    elif tag == 2:
        if path:
            path.pop()
    elif tag == 3:
        plen, noff = struct.unpack_from(">II", blob, p)
        p += 8
        p += (plen + 3) // 4 * 4
    elif tag == 9:
        break

print("total nodes parsed: %d" % len(nodes))

# 1. All crgctrl/sctrl/pmctrl containers with reg+status
for np_, props in nodes:
    leaf = np_.split("/")[-1]
    if leaf.startswith(("crgctrl", "sctrl", "clk_pmctrl", "pmctrl", "pmu")):
        reg = props.get("reg", b"").hex()
        st = props.get("status", b"").hex()
        comp = props.get("compatible", b"").hex()
        print("CONTAINER %-90s reg=%s status=%s" % (np_, reg, st))
        try:
            print("          compatible=%r" % cstr(comp, 0))
        except Exception:
            pass

# 2. clk_sd / hclk_sd nodes: full path + parent container reg
for np_, props in nodes:
    leaf = np_.split("/")[-1]
    if leaf in ("clk_sd", "hclk_sd", "clkgt_mmc1", "clkgt_mmc0", "clk_sdio0"):
        parent = np_.rsplit("/", 1)[0]
        preg = b""
        for np2, props2 in nodes:
            if np2 == parent:
                preg = props2.get("reg", b"")
        ph = props.get("phandle", b"")
        print("NODE %-80s phandle=%s" % (np_, ph.hex()))
        for k in ("clocks", "hisilicon,hi3xxx-clkgate", "hisilicon,clkgate",
                  "hisilicon,clkdiv", "hisilicon,clkmux-reg", "clock-fpga"):
            if k in props:
                print("      %s = %s" % (k, props[k].hex()))
        print("      parent = %s (reg=%s)" % (parent, preg.hex()))
