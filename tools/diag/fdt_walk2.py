#!/usr/bin/env python3
"""Second pass: display path, bootargs, and the USB controller in detail.

Saves the complete flattened property list for later reference and prints the
nodes that matter for the first bring-up attempts.
"""
import struct
import sys

FDT_MAGIC = 0xD00DFEED
PATH = "firmware/ane_dtb/fdt.dtb"
FDT_BEGIN_NODE, FDT_END_NODE, FDT_PROP, FDT_NOP, FDT_END = 1, 2, 3, 4, 9


def walk(blob):
    off_struct, off_strings = struct.unpack_from(">II", blob, 8)
    p = off_struct
    stack, out = [], []
    while p + 4 <= len(blob):
        (tok,) = struct.unpack_from(">I", blob, p)
        p += 4
        if tok == FDT_END:
            break
        if tok == FDT_NOP:
            continue
        if tok == FDT_BEGIN_NODE:
            end = blob.index(b"\0", p)
            stack.append(blob[p:end].decode("latin-1"))
            p = (end + 1 + 3) & ~3
        elif tok == FDT_END_NODE:
            if stack:
                stack.pop()
        elif tok == FDT_PROP:
            length, nameoff = struct.unpack_from(">II", blob, p)
            p += 8
            val = blob[p:p + length]
            p = (p + length + 3) & ~3
            end = blob.index(b"\0", off_strings + nameoff)
            out.append(("/" + "/".join(n for n in stack if n),
                        blob[off_strings + nameoff:end].decode("latin-1"), val))
    return out


def fmt(val):
    if len(val) % 4 == 0 and len(val) <= 64:
        cells = struct.unpack(f">{len(val)//4}I", val)
        if all(c == 0 or c > 0xFF for c in cells) or any(c > 0xFFFF for c in cells):
            return " ".join(f"{c:#x}" for c in cells)
    s = val[:120].decode("latin-1").replace("\0", " | ")
    return repr(s)


def dump(props, filt, title, props_wanted=None, limit=200):
    print(f"\n### {title}")
    n = 0
    for path, pname, val in props:
        if not filt(path):
            continue
        if props_wanted and pname not in props_wanted:
            continue
        print(f"  {path}  [{pname}] = {fmt(val)}")
        n += 1
        if n >= limit:
            print(f"  ... ({limit} shown)")
            return
    if n == 0:
        print("  (none)")


def main():
    blob = open(PATH, "rb").read()
    props = walk(blob)
    with open("firmware/ane_dtb/fdt_properties.txt", "w") as fh:
        for path, pname, val in props:
            fh.write(f"{path}\t{pname}\t{val[:64].hex()}\n")
    print(f"wrote firmware/ane_dtb/fdt_properties.txt ({len(props)} properties)")

    want = {"compatible", "reg", "status", "interrupts", "clocks", "clock-names",
            "bootargs", "stdout-path", "huawei,lcd_panel_type", "huawei,lcd_panel",
            "use-dsi", "dsi,flags", "panel-width-mm", "panel-height-mm",
            "dr_mode", "maximum-speed", "hisilicon,usb2-phy", "phy-names", "phys"}

    dump(props, lambda p: p.startswith("/chosen") or p == "/chosen", "chosen", want)
    dump(props, lambda p: "dsi" in p.lower() or "lcd" in p.lower() or "panel" in p.lower(),
         "display path", want, limit=60)
    dump(props, lambda p: p.lower().startswith("/usb") or "/phy" in p.lower(),
         "usb controllers and phys", want, limit=60)
    dump(props, lambda p: p in ("/", ""), "root", want)
    return 0


if __name__ == "__main__":
    sys.exit(main())
