import pathlib

# 1) seed the USB registers in the WITH_SEED block (qemu can't map the real MRs)
seed = """
    /* USB field seeds (the qemu cannot map the ANE's peripherals) */
    movz x26, #((USB_CORE) >> 16), lsl #16
    movk x26, #((USB_CORE) & 0xffff)
    movz w10, #0x5678
    movk w10, #0x1234, lsl #16
    str  w10, [x26, #0x40]             /* GSNPSID = 0x12345678 */
    movz w10, #0xC3D4
    movk w10, #0xA1B2, lsl #16
    str  w10, [x26, #0x800]            /* DCFG    = 0xA1B2C3D4 */
    movz w10, #0xF001
    str  w10, [x26, #0x804]            /* DCTL    = 0x0000F001 */
    movz w10, #0x0001
    movk w10, #0x0007, lsl #16
    str  w10, [x26, #0x808]            /* DSTS    = 0x00070001 */
    movz x26, #((USB_AHB) >> 16), lsl #16
    movk x26, #((USB_AHB) & 0xffff)
    movz w10, #0x0001
    movk w10, #0x0003, lsl #16
    str  w10, [x26, #0x00]             /* AHBIF CTRL0 = 0x00030001 */
    mov  w10, #0x0C
    str  w10, [x26, #0x3C]             /* BC_STS0     = 0x0000000C */
.endif
"""
p = pathlib.Path("/home/placeless/dev/p20-root/ane_log_probe.S")
s = p.read_text()
old = "\n.endif\n\n    /* ---- build the text string at TEXT_BUF ---- */"
assert s.count(old) == 1
s = s.replace(old, seed + "\n    /* ---- build the text string at TEXT_BUF ---- */")
p.write_text(s)
print("USB seed inserted before .endif")

# 2) .sh: defsyms + expected text
q = pathlib.Path("/home/placeless/dev/p20-root/ane_log_probe.sh")
t = q.read_text()
def rep(old, new, n=1):
    global t
    c = t.count(old)
    assert c == n, f"count {c} != {n}: {old[:60]!r}"
    t = t.replace(old, new)

# device defsyms: insert USB bases after PMSG_BASE
rep("  --defsym PMSG_BASE=0x348E0000 \\",
    "  --defsym PMSG_BASE=0x348E0000 \\\n  --defsym USB_CORE=0xFF100000 --defsym USB_AHB=0xFF200000 \\")
rep("  --defsym PMSG_BASE=0x45020000 \\",
    "  --defsym PMSG_BASE=0x45020000 \\\n  --defsym USB_CORE=0x47000000 --defsym USB_AHB=0x47001000 \\")

# expected: 405 tail + the USB block + the RC
rep('tail = b"VBCDEFGHIJKL" + bytes(528)',
    '''tail = b"VBCDEFGHIJKL" + bytes(393)
usb = (b"USB CORE FF100000 AHBIF FF200000" + b" " * 14
       + b"ID=12345678 CFG=A1B2C3D4 CTL=0000F001" + b" " * 8
       + b"DST=00070001 AHB=00030001 BC=0000000C" + b" " * 8)''')
rep('s = tail.decode("latin-1")',
    's = (tail + usb).decode("latin-1")')
q.write_text(t)
print("sh: defsyms + expected updated (405 log + 135 USB + 90 RC)")
