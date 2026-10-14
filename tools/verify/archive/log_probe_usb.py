import pathlib

p = pathlib.Path("/home/placeless/dev/p20-root/ane_log_probe.S")
s = p.read_text()

def rep(old, new, n=1):
    global s
    c = s.count(old)
    assert c == n, f"count {c} != {n}: {old[:60]!r}"
    s = s.replace(old, new)

# log tail 540 -> 405 (nine rows); USB block takes three, RC keeps two = 14 rows
rep("    mov  w25, #540", "    mov  w25, #405")
rep("    mov  w24, #540", "    mov  w24, #405")

# Build the USB section: header row, then two rows of label=value pairs.
def lit(text, comment=""):
    out = []
    for ch in text:
        out.append(f"    mov  w21, #{ord(ch)}")
        out.append("    strb w21, [x28], #1")
    if comment:
        out.append(f"    /* {comment} */")
    return "\n".join(out)

def hex8(sym, off, comment):
    return f"""    movz x26, #(({sym}) >> 16), lsl #16
    movk x26, #(({sym}) & 0xffff)
    ldr  w22, [x26, #{off}]
    mov  w23, #28                      /* {comment}: 8 nibbles, MSB first */
44: lsr  w21, w22, w23
    nib2asc
    strb w21, [x28], #1
    subs w23, w23, #4
    b.pl 44b"""

row1 = "USB CORE FF100000 AHBIF FF200000"
row1 = row1 + " " * (45 - len(row1))
row2 = "ID=XXXXXXXX CFG=XXXXXXXX CTL=XXXXXXXX"
row3 = "DST=XXXXXXXX AHB=XXXXXXXX BC=XXXXXXXX"

usb = []
usb.append("")
usb.append("    /* USB gadget fields: DWC-OTG core id/config/control/status plus")
usb.append("     * the AHBIF pull-down control and charger state - the values the")
usb.append("     * host needs to see the port enumerate (addresses from the DT). */")
usb.append(lit(row1, "USB CORE FF100000 AHBIF FF200000"))
usb.append(lit("ID="))
usb.append(hex8("USB_CORE", "0x40", "GSNPSID"))
usb.append(lit(" CFG="))
usb.append(hex8("USB_CORE", "0x800", "DCFG"))
usb.append(lit(" CTL="))
usb.append(hex8("USB_CORE", "0x804", "DCTL"))
usb.append(lit("        ", ""))
usb.append(lit("DST="))
usb.append(hex8("USB_CORE", "0x808", "DSTS"))
usb.append(lit(" AHB="))
usb.append(hex8("USB_AHB", "0x00", "AHBIF_CTRL0"))
usb.append(lit(" BC="))
usb.append(hex8("USB_AHB", "0x3C", "BC_STS0"))
usb.append(lit("        ", ""))
usb_frag = "\n".join(usb) + "\n"
_ = (row2, row3)  # labels shown inline; kept for the .sh's expected builder

anchor = """
    /* record lines: "RC " + 24 hex chars (12 bytes), then 24 hex + 9 pad */"""
assert s.count(anchor) == 1
s = s.replace(anchor, "\n" + usb_frag + anchor)

p.write_text(s)
print("USB section inserted; log tail 405; rows: 9 log + 3 USB + 2 RC = 14")
