import pathlib

p = pathlib.Path("/home/placeless/dev/p20-root/ane_log_probe.S")
s = p.read_text()
def rep(old, new, n=1):
    global s
    c = s.count(old)
    assert c == n, f"anchor count {c} != {n}: {old[:60]!r}"
    s = s.replace(old, new)

# --- column pitch 32 -> 24, x base 16 -> 8
rep("""    lsl  w10, w5, #5                   /* col*32 */
    add  w10, w10, #16
    lsl  w10, w10, #2                  /* (16+col*32)*4 */""",
    """    add  w10, w5, w5, lsl #1           /* col*3 */
    lsl  w10, w10, #3                  /* col*24 */
    add  w10, w10, #8
    /* (8+col*24) already in pixels */""")

# --- line pitch 40 -> 30, y base 16 -> 8
rep("""    lsl  w8, w4, #3                    /* line*8 */
    add  w8, w8, w4, lsl #5            /* + line*32 = line*40 */
    add  w8, w8, #16""",
    """    movz w8, #30                       /* line*30 */
    mul  w8, w4, w8
    add  w8, w8, #8""")

# --- gx step 16 -> 12
rep("""    lsl  w17, w16, #4                  /* gx*16 */
    add  x18, x8, w17, uxtw
    stp  x12, x12, [x18]
    add  x18, x18, x13
    stp  x12, x12, [x18]
    add  x18, x18, x13
    stp  x12, x12, [x18]
    add  x18, x18, x13
    stp  x12, x12, [x18]""",
    """    lsl  w17, w16, #2                  /* gx*4 */
    add  w17, w17, w16, lsl #3         /* gx*12 */
    add  x18, x8, w17, uxtw
    str  w12, [x18]
    str  w12, [x18, #4]
    str  w12, [x18, #8]
    add  x18, x18, x13
    str  w12, [x18]
    str  w12, [x18, #4]
    str  w12, [x18, #8]
    add  x18, x18, x13
    str  w12, [x18]
    str  w12, [x18, #4]
    str  w12, [x18, #8]""")

# --- glyph row step: 4 scanlines -> 3
rep("""    add  x8, x8, x13
    add  x8, x8, x13
    add  x8, x8, x13
    add  x8, x8, x13                   /* next glyph row: +4 scanlines */""",
    """    add  x8, x8, x13
    add  x8, x8, x13
    add  x8, x8, x13                   /* next glyph row: +3 scanlines */""")

# --- counts: 45 cols, 14 lines
rep("    cmp  w5, #33", "    cmp  w5, #45")
rep("    cmp  w4, #26", "    cmp  w4, #14")
rep("/* ---- render 6x33 glyphs into the bitmap (cyan, 4x scale) ---- */",
    "/* ---- render 14x45 glyphs into the bitmap (cyan, 3x scale) ---- */")
rep("    mov  w25, #792", "    mov  w25, #540")
rep("    mov  w24, #792", "    mov  w24, #540")
rep("    mov  w23, #6", "    mov  w23, #18")
rep("19: mov  w23, #9", "19: mov  w23, #21")

# --- comment about the text buffer length
rep("/* up to ~1.8KB of the", "/* up to 540 chars of the") if "/* up to ~1.8KB of the" in s else None
p.write_text(s)
print("3x/14-row/540-char edits applied")
