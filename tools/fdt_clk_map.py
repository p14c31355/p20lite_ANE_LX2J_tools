#!/usr/bin/env python3
"""Map CRG clock-node phandles to names and dump the ones the port needs."""
import struct

blob = open("firmware/ane_dtb/fdt.dtb", "rb").read()
off_struct, off_strings = struct.unpack_from(">II", blob, 8)


def cstr(b, o):
    e = b.index(b"\0", o)
    return b[o:e].decode("utf-8", "replace")


# Pass 1: node -> (phandle, name) for every node under crgctrl.
nodes = {}
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
        if name.startswith("clk_") or name in ("hclk_emmc0", "clk_emmc0") or "mmc" in name:
            # scan this node's props only
            save = p
            ph = None
            props = []
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
                    if pname in ("hisilicon,clkdiv", "hisilicon,clkmux-reg",
                                 "hisilicon,hi3xxx-clkgate", "clocks",
                                 "clock-div", "clock-mult", "clock-output-names"):
                        props.append((pname, val.hex() if plen <= 16 else "len%d" % plen))
                    p += (plen + 3) // 4 * 4
                elif t2 == 1:
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
                else:
                    break
            if ph is not None:
                nodes[ph] = (cur.split("/")[-1], props)
            p = save
        # fall through: continue walking from p (children handled by main loop)
    elif tag == 2:
        path.pop()
    elif tag == 3:
        plen, noff = struct.unpack_from(">II", blob, p)
        p += 8
        p += (plen + 3) // 4 * 4
    elif tag == 9:
        break

for ph in sorted(nodes):
    name, props = nodes[ph]
    print("0x%03x %-24s %s" % (ph, name, " ".join("%s=%s" % kv for kv in props)))
print()
print("dwmmc1 clocks = 0x1a4, 0x1a5 ->", nodes.get(0x1A4), nodes.get(0x1A5))
print("dwmmc2 clocks = 0x1bf, 0x1c0 ->", nodes.get(0x1BF), nodes.get(0x1C0))
