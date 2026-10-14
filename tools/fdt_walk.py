#!/usr/bin/env python3
"""Walk the ANE-LX2J device tree and print what the port needs.

Minimal FDT parser - no dtc on this host - that reports the memory map, the
UARTs, the USB controllers and the display path, with their addresses and the
properties that matter for bring-up.
"""
import struct
import sys

FDT_MAGIC = 0xD00DFEED
PATH = "firmware/ane_dtb/fdt.dtb"

FDT_BEGIN_NODE = 1
FDT_END_NODE = 2
FDT_PROP = 3
FDT_NOP = 4
FDT_END = 9


def read_strings(blob, off, size):
    return blob[off:off + size]


def walk(blob):
    # header: magic, totalsize, off_dt_struct, off_dt_strings, off_mem_rsvmap,
    #         version, last_comp_version, boot_cpuid_phys, size_dt_strings, size_dt_struct
    off_struct, off_strings = struct.unpack_from(">II", blob, 8)
    size_strings, = struct.unpack_from(">I", blob, 32)
    p = off_struct
    stack = []
    path = "/"
    out = []
    while True:
        if p + 4 > len(blob):
            break
        (tok,) = struct.unpack_from(">I", blob, p)
        p += 4
        if tok == FDT_END:
            break
        if tok == FDT_NOP:
            continue
        if tok == FDT_BEGIN_NODE:
            end = blob.index(b"\0", p)
            name = blob[p:end].decode("latin-1")
            p = end + 1
            p = (p + 3) & ~3
            stack.append(name)
            path = "/" + "/".join(n for n in stack if n)
        elif tok == FDT_END_NODE:
            if stack:
                stack.pop()
        elif tok == FDT_PROP:
            length, nameoff = struct.unpack_from(">II", blob, p)
            p += 8
            val = blob[p:p + length]
            p = (p + length + 3) & ~3
            end = blob.index(b"\0", off_strings + nameoff)
            pname = blob[off_strings + nameoff:end].decode("latin-1")
            out.append((path, pname, val))
    return out


def main():
    blob = open(PATH, "rb").read()
    magic, = struct.unpack_from(">I", blob, 0)
    if magic != FDT_MAGIC:
        print(f"not an FDT: {magic:#x}")
        return 1
    print(f"FDT {len(blob):,} bytes")
    props = walk(blob)
    print(f"properties: {len(props)}")

    def show(node_filter, title, prop_filter=None, limit=14):
        print()
        print(f"### {title}")
        seen = set()
        n = 0
        for path, pname, val in props:
            if node_filter(path) and (prop_filter is None or pname in prop_filter):
                if path not in seen:
                    seen.add(path)
                if pname in ("compatible", "reg", "interrupts", "status",
                             "clock-names", "clocks", "huawei,lcd_panel_type",
                             "huawei,lcd_panel", "dr_mode", "phy-names",
                             "phys", "vbus-gpio", "maximum-speed"):
                    if pname in ("reg", "clocks", "interrupts"):
                        cells = struct.unpack(f">{len(val)//4}I", val[:len(val)//4*4])
                        shown = " ".join(f"{c:#x}" for c in cells[:8])
                    else:
                        shown = val[:100].decode("latin-1").replace("\0", " | ")
                    print(f"  {path}\n    {pname} = {shown}")
                    n += 1
                    if n > limit:
                        return
        if n == 0:
            print("  (none)")

    show(lambda p: "memory" in p, "memory")
    show(lambda p: "uart" in p or "serial" in p, "uart/serial")
    show(lambda p: "usb" in p.lower() or "dwc" in p.lower(), "usb")
    show(lambda p: "dsi" in p or "lcd" in p or "panel" in p, "display")
    show(lambda p: "chosen" in p or p == "/chosen", "chosen/bootargs")
    return 0


if __name__ == "__main__":
    sys.exit(main())
