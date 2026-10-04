import pathlib

p = pathlib.Path("/home/placeless/dev/p20-root/ane_log_probe.S")
s = p.read_text()

start_marker = "    /* ten value entries, two per line:"
end_marker = "    b.ne 9b\n"
i = s.find(start_marker)
assert i >= 0, "start not found"
j = s.find(end_marker, i)
assert j >= 0, "end not found"
j += len(end_marker)

new_block = """    /* ---- log tail: the durable text log lives in the pmsg zone's data
     * area - 12 header bytes at PMSG_BASE (sig/start/size), then `size`
     * bytes of text. Render the last 330 chars as ten 33-char rows. The
     * glyph map blanks anything outside digits/A-F/V/R, so punctuation
     * falls out and letters arrive pre-folded to upper case by the tee. */
    movz x27, #((PMSG_BASE) >> 16), lsl #16
    movk x27, #((PMSG_BASE) & 0xffff)
    ldr  w26, [x27, #8]                /* stored text length */
    mov  w25, #330
    cmp  w26, w25
    b.lo 40f
    sub  w26, w26, w25
    b    41f
40: mov  w26, #0
41: add  x27, x27, w26, uxtw
    add  x27, x27, #12                 /* first byte of the rendered tail */
    mov  w24, #330
42: ldrb w21, [x27], #1
    strb w21, [x28], #1
    subs w24, w24, #1
    b.ne 42b

"""
s = s[:i] + new_block + s[j:]

seed_marker = """    movz w10, #0x4430, lsl #16
    str  w10, [x19, #0xA8]
.endif
"""
assert s.count(seed_marker) == 1
seed_new = """    movz w10, #0x4430, lsl #16
    str  w10, [x19, #0xA8]
    /* a known log text for the reader proof: "ABCDEFGHIJKL" */
    movz x26, #((PMSG_BASE) >> 16), lsl #16
    movk x26, #((PMSG_BASE) & 0xffff)
    movz w10, #0x4241                /* "AB" */
    movk w10, #0x4443, lsl #16       /* "CD" */
    str  w10, [x26, #12]
    movz w10, #0x4645                /* "EF" */
    movk w10, #0x4847, lsl #16       /* "GH" */
    str  w10, [x26, #16]
    movz w10, #0x4A49                /* "IJ" */
    movk w10, #0x4C4B, lsl #16       /* "KL" */
    str  w10, [x26, #20]
    mov  w10, #12
    str  w10, [x26, #8]              /* size = 12 */
.endif
"""
s = s.replace(seed_marker, seed_new, 1)
p.write_text(s)
print("spliced ok; new length", len(s), "chars")
