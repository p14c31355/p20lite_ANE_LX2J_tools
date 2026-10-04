/* Text probe: print data to the phone screen as readable cyan text.
 *
 * The readout bottleneck has been the display: bands give one number per
 * device cycle. This probe instead renders arbitrary hex data as 8x8 font
 * glyphs (cyan on black, scaled 4x) and blits the same bitmap to every
 * plausible display channel buffer - whichever buffer the panel really
 * scans shows the text, and the camera reads hundreds of characters in one
 * run.
 *
 * Content (6 lines, 33 chars each):
 *   V0..V9 = the ten display-channel DMA_DATA_ADDR0 values (8 hex digits)
 *   RC     = the step-mark record: magic, count, then 16 mark bytes as hex
 *
 * Safety (same math as ane_marks_final): no relocation; the blit extent is
 * 0x110000 and any candidate whose range [v, v+extent) would intersect the
 * code window [P_LO, P_HI) is refused outright, so a blit can never sweep
 * the running code. Ramoops window protected too.
 */

.section .text, "ax"
.balign 4
.global _start

.macro spin count, repeats=1
    movz w12, #((\repeats) & 0xffff)
1:  movz w11, #((\count >> 16) & 0xffff)
    movk w11, #((\count >> 32) & 0xffff), lsl #16
2:  subs w11, w11, #1
    b.ne 2b
    subs w12, w12, #1
    b.ne 1b
.endm

/* ASCII hex digit of w21's low nibble -> w21 */
.macro nib2asc
    and  w21, w21, #0xF
    add  w21, w21, #0x30
    cmp  w21, #0x39
    b.ls 90f
    add  w21, w21, #7
90:
.endm

/* blit: copy the bitmap to w20 if w20 is plausible, outside the code
 * window [P_LO, P_HI) sweep (unless SKIP_P=0) and outside ramoops;
 * clobbers w9-w11/x9-w13 */
.macro blit
    movz w9, #0x0010, lsl #16
    cmp  w20, w9
    b.lo 89f
    movz w9, #((GATE_HI) >> 16), lsl #16
    movk w9, #((GATE_HI) & 0xffff)
    cmp  w20, w9
    b.hs 89f
    movz w10, #((RENDER_LEN) >> 16), lsl #16
    movk w10, #((RENDER_LEN) & 0xffff)
    add  w10, w10, w20
.if SKIP_P
    movz w11, #((P_LO) >> 16), lsl #16
    movk w11, #((P_LO) & 0xffff)
    movz w9, #((P_HI) >> 16), lsl #16
    movk w9, #((P_HI) & 0xffff)
    cmp  w20, w9
    b.hs 88f
    cmp  w10, w11
    b.ls 88f
    b    89f
.endif
88: movz w11, #((RAMO_WIN_START) >> 16), lsl #16
    movk w11, #((RAMO_WIN_START) & 0xffff)
    movz w9, #((RAMO_WIN_END) >> 16), lsl #16
    movk w9, #((RAMO_WIN_END) & 0xffff)
    cmp  w10, w11
    b.ls 87f
    cmp  w20, w9
    b.hs 87f
    b    89f
87: movz w9, #((BITMAP) >> 16), lsl #16
    movk w9, #((BITMAP) & 0xffff)
    movz w11, #((BITMAP_LEN) >> 16), lsl #16
    movk w11, #((BITMAP_LEN) & 0xffff)
    add  x11, x11, x9
    add  x10, x20, xzr                  /* dst = w20 zero-extended */
82: ldp  x12, x13, [x9], #16
    stp  x12, x13, [x10], #16
    cmp  x9, x11
    b.lo 82b
89:
.endm

_start:
    /* MMU off first: the loader hands over with it on and its tables do not
     * cover the regions we touch (measured - the first access faults). */
    mrs  x0, CurrentEL
    cmp  x0, #0x4
    b.eq 1f
    cmp  x0, #0x8
    b.eq 2f
    b    3f
1:  mrs  x1, sctlr_el1
    tbnz x1, #0, 4f
    b    3f
2:  mrs  x1, sctlr_el2
    tbnz x1, #0, 5f
    b    3f
4:  bic  x1, x1, #1
    msr  sctlr_el1, x1
    isb
    b    3f
5:  bic  x1, x1, #1
    msr  sctlr_el2, x1
    isb
3:

.if WITH_SEED
    /* QEMU: plant the marks record and a G1 slot value */
    movz x27, #((MARKS_BASE) >> 16), lsl #16
    movk x27, #((MARKS_BASE) & 0xffff)
    movz w10, #0x4E41
    movk w10, #0x4D45, lsl #16
    str  w10, [x27]
    mov  w10, #3
    str  w10, [x27, #4]
    movz w10, #0x3231
    movk w10, #0x0033, lsl #16
    str  w10, [x27, #8]
    movz x19, #((RCH_G1_BASE) >> 16), lsl #16
    movk x19, #((RCH_G1_BASE) & 0xffff)
    movz w10, #0x4410, lsl #16
    str  w10, [x19, #0x60]
    movz w10, #0x4420, lsl #16
    str  w10, [x19, #0x84]
    movz w10, #0x4430, lsl #16
    str  w10, [x19, #0xA8]
    /* a known log text for the reader proof: "ABCDEFGHIJKL" */
    movz x26, #((PMSG_BASE) >> 16), lsl #16
    movk x26, #((PMSG_BASE) & 0xffff)
    movz w10, #0x4256                /* "VB" - leads with V so the glyph */
    movk w10, #0x4443, lsl #16       /* "CD"   pixel check stays valid */
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

    /* ---- build the text string at TEXT_BUF ---- */
    movz x28, #((TEXT_BUF) >> 16), lsl #16
    movk x28, #((TEXT_BUF) & 0xffff)

    /* ---- log tail: the durable text log lives in the pmsg zone's data
     * area - 12 header bytes at PMSG_BASE (sig/start/size), then `size`
     * bytes of text. Render the last 330 chars as ten 33-char rows. The
     * glyph map blanks anything outside digits/A-F/V/R, so punctuation
     * falls out and letters arrive pre-folded to upper case by the tee. */
    movz x27, #((PMSG_BASE) >> 16), lsl #16
    movk x27, #((PMSG_BASE) & 0xffff)
    ldr  w26, [x27, #8]                /* stored text length */
    mov  w25, #540
    cmp  w26, w25
    b.lo 40f
    sub  w26, w26, w25
    b    41f
40: mov  w26, #0
41: add  x27, x27, w26, uxtw
    add  x27, x27, #12                 /* first byte of the rendered tail */
    mov  w24, #540
42: ldrb w21, [x27], #1
    strb w21, [x28], #1
    subs w24, w24, #1
    b.ne 42b



    /* record lines: "RC " + 24 hex chars (12 bytes), then 24 hex + 9 pad */
    mov  w21, #0x52                   /* 'R' */
    strb w21, [x28], #1
    mov  w21, #0x43                   /* 'C' */
    strb w21, [x28], #1
    mov  w21, #0x20
    strb w21, [x28], #1
    movz x27, #((MARKS_BASE) >> 16), lsl #16
    movk x27, #((MARKS_BASE) & 0xffff)
    mov  w24, #0                       /* byte index 0..23 */
17: ldrb w25, [x27, w24, uxtw]
    lsr  w21, w25, #4
    nib2asc
    strb w21, [x28], #1
    mov  w21, w25
    nib2asc
    strb w21, [x28], #1
    add  w24, w24, #1
    cmp  w24, #12
    b.eq 18f
    cmp  w24, #24
    b.ne 17b
    /* second record line: 24 chars done; pad 9 spaces total does not fit -
      * first line holds "RC "+24 = 27 chars, pad 6 spaces to reach 33 */
18: cmp  w24, #12
    b.ne 19f
    mov  w23, #18
20: mov  w21, #0x20
    strb w21, [x28], #1
    subs w23, w23, #1
    b.ne 20b
    b    17b                           /* continue with bytes 12..23 */
19: mov  w23, #21
21: mov  w21, #0x20
    strb w21, [x28], #1
    subs w23, w23, #1
    b.ne 21b

    /* ---- clear the bitmap to black (0x10E000 bytes) ---- */
    movz x9, #((BITMAP) >> 16), lsl #16
    movk x9, #((BITMAP) & 0xffff)
    movz x10, #0x0000
    movk x10, #0xFF00, lsl #16         /* opaque black 0xFF000000 */
    orr  x10, x10, x10, lsl #32
    movz x11, #((BITMAP_LEN) >> 16), lsl #16
    movk x11, #((BITMAP_LEN) & 0xffff)
    add  x11, x11, x9
22: stp  x10, x10, [x9], #16
    cmp  x9, x11
    b.lo 22b

    /* ---- render 14x45 glyphs into the bitmap (cyan, 3x scale) ---- */
    movz x2, #((TEXT_BUF) >> 16), lsl #16
    movk x2, #((TEXT_BUF) & 0xffff)
    movz x12, #0xFF00
    movk x12, #0xFFFF, lsl #16         /* cyan 0xFFFFFF00 */
    orr  x12, x12, x12, lsl #32
    movz w13, #0x10E0                  /* screen row stride 4320 */
    mov  w4, #0                       /* line 0..5 */
23: mov  w5, #0                       /* col 0..32 */
24: ldrb w6, [x2], #1                 /* char */
    /* map char -> glyph index w7: 0x20..0x5F are glyphs 0..63, else space */
    sub  w7, w6, #0x20
    cmp  w7, #0x3F
    b.ls 25f
    mov  w7, #0
25: /* glyph cell top-left pixel (x = 16 + col*32, y = 16 + line*40) */
    movz w8, #30                       /* line*30 */
    mul  w8, w4, w8
    add  w8, w8, #8
    movz w9, #((BITMAP) >> 16), lsl #16
    movk w9, #((BITMAP) & 0xffff)
    mul  w8, w8, w13                   /* y*4320 */
    add  x8, x9, w8, uxtw
    add  w10, w5, w5, lsl #1           /* col*3 */
    lsl  w10, w10, #3                  /* col*24 */
    add  w10, w10, #8
    lsl  w10, w10, #2                  /* (8+col*24)*4 = bytes */
    add  x8, x8, w10, uxtw             /* cell top-left byte address */
    /* glyph data pointer */
    adr  x9, FONT
    lsl  x7, x7, #3
    add  x9, x9, x7
    mov  w14, #0                       /* gy 0..7; x8 advances 4 rows/gy */
29: ldrb w15, [x9], #1
    mov  w16, #0                       /* gx 0..7 */
30: tst  w15, #0x80
    b.eq 31f
    /* write 4x4 cyan block at x8 + gx*16 */
    lsl  w17, w16, #2                  /* gx*4 */
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
    str  w12, [x18, #8]
31: lsl  w15, w15, #1
    add  w16, w16, #1
    cmp  w16, #8
    b.ne 30b
    add  x8, x8, x13
    add  x8, x8, x13
    add  x8, x8, x13                   /* next glyph row: +3 scanlines */
    add  w14, w14, #1
    cmp  w14, #8
    b.ne 29b
    add  w5, w5, #1
    cmp  w5, #45
    b.ne 24b
    add  w4, w4, #1
    cmp  w4, #14
    b.ne 23b

    /* ---- blit the bitmap to the candidates ----
     * G1 and WCH0 first (the two candidates the cyan/teal fill evidence
     * points at); if a later blit crashes in the low-window sweep zone,
     * their text is already on screen. */
    movz w19, #((RCH_G1_BASE) >> 16), lsl #16
    movk w19, #((RCH_G1_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    blit
    ldr  w20, [x19, #0x84]
    blit
    ldr  w20, [x19, #0xA8]
    blit
    movz w19, #((RCH_WCH0_BASE) >> 16), lsl #16
    movk w19, #((RCH_WCH0_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    blit
    ldr  w20, [x19, #0x84]
    blit
    ldr  w20, [x19, #0xA8]
    blit
    movz w19, #((RCH_VG0_BASE) >> 16), lsl #16
    movk w19, #((RCH_VG0_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    blit
    ldr  w20, [x19, #0x84]
    blit
    ldr  w20, [x19, #0xA8]
    blit
    movz w19, #((RCH_VG1_BASE) >> 16), lsl #16
    movk w19, #((RCH_VG1_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    blit
    ldr  w20, [x19, #0x84]
    blit
    ldr  w20, [x19, #0xA8]
    blit
    movz w19, #((RCH_G0_BASE) >> 16), lsl #16
    movk w19, #((RCH_G0_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    blit
    ldr  w20, [x19, #0x84]
    blit
    ldr  w20, [x19, #0xA8]
    blit
    movz w19, #((RCH_D0_BASE) >> 16), lsl #16
    movk w19, #((RCH_D0_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    blit
    ldr  w20, [x19, #0x84]
    blit
    ldr  w20, [x19, #0xA8]
    blit
    movz w19, #((RCH_D1_BASE) >> 16), lsl #16
    movk w19, #((RCH_D1_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    blit
    ldr  w20, [x19, #0x84]
    blit
    ldr  w20, [x19, #0xA8]
    blit
    movz w19, #((RCH_D2_BASE) >> 16), lsl #16
    movk w19, #((RCH_D2_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    blit
    ldr  w20, [x19, #0x84]
    blit
    ldr  w20, [x19, #0xA8]
    blit
    movz w19, #((RCH_D3_BASE) >> 16), lsl #16
    movk w19, #((RCH_D3_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    blit
    ldr  w20, [x19, #0x84]
    blit
    ldr  w20, [x19, #0xA8]
    blit
    movz w19, #((RCH_WCH0_BASE) >> 16), lsl #16
    movk w19, #((RCH_WCH0_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    blit
    ldr  w20, [x19, #0x84]
    blit
    ldr  w20, [x19, #0xA8]
    blit
    movz w19, #((RCH_WCH1_BASE) >> 16), lsl #16
    movk w19, #((RCH_WCH1_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    blit
    ldr  w20, [x19, #0x84]
    blit
    ldr  w20, [x19, #0xA8]
    blit
    /* G1 last: strongest candidate for the scanned frame */
    movz w19, #((RCH_G1_BASE) >> 16), lsl #16
    movk w19, #((RCH_G1_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    blit
    ldr  w20, [x19, #0x84]
    blit
    ldr  w20, [x19, #0xA8]
    blit
    /* fixed fallback (the kernel's reserved graphic region) */
    movz w20, #((FALLBACK_BASE) >> 16), lsl #16
    movk w20, #((FALLBACK_BASE) & 0xffff)
    blit

    spin SPIN_HOLD, HOLD_REPEATS
.Lhang:
    wfe
    b    .Lhang

.balign 8
FONT:
    .byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00   /* 0x20 ' ' */
    .byte 0x18,0x3C,0x3C,0x18,0x18,0x00,0x18,0x00   /* 0x21 '!' */
    .byte 0x6C,0x6C,0x00,0x00,0x00,0x00,0x00,0x00   /* 0x22 '"' */
    .byte 0x6C,0x6C,0xFE,0x6C,0xFE,0x6C,0x6C,0x00   /* 0x23 '#' */
    .byte 0x30,0x7C,0xC0,0x78,0x0C,0xF8,0x30,0x00   /* 0x24 '$' */
    .byte 0x00,0xC6,0xCC,0x18,0x30,0x66,0xC6,0x00   /* 0x25 '%' */
    .byte 0x38,0x6C,0x38,0x76,0xDC,0xCC,0x76,0x00   /* 0x26 '&' */
    .byte 0x60,0x60,0xC0,0x00,0x00,0x00,0x00,0x00   /* 0x27 ''' */
    .byte 0x18,0x30,0x60,0x60,0x60,0x30,0x18,0x00   /* 0x28 '(' */
    .byte 0x60,0x30,0x18,0x18,0x18,0x30,0x60,0x00   /* 0x29 ')' */
    .byte 0x00,0x66,0x3C,0xFF,0x3C,0x66,0x00,0x00   /* 0x2A '*' */
    .byte 0x00,0x30,0x30,0xFC,0x30,0x30,0x00,0x00   /* 0x2B '+' */
    .byte 0x00,0x00,0x00,0x00,0x00,0x30,0x30,0x60   /* 0x2C ',' */
    .byte 0x00,0x00,0x00,0xFC,0x00,0x00,0x00,0x00   /* 0x2D '-' */
    .byte 0x00,0x00,0x00,0x00,0x00,0x30,0x30,0x00   /* 0x2E '.' */
    .byte 0x06,0x0C,0x18,0x30,0x60,0xC0,0x80,0x00   /* 0x2F '/' */
    .byte 0x7C,0xC6,0xCE,0xDE,0xF6,0xE6,0x7C,0x00   /* 0x30 '0' */
    .byte 0x30,0x70,0x30,0x30,0x30,0x30,0xFC,0x00   /* 0x31 '1' */
    .byte 0x78,0xCC,0x0C,0x38,0x60,0xCC,0xFC,0x00   /* 0x32 '2' */
    .byte 0x78,0xCC,0x0C,0x38,0x0C,0xCC,0x78,0x00   /* 0x33 '3' */
    .byte 0x1C,0x3C,0x6C,0xCC,0xFE,0x0C,0x1E,0x00   /* 0x34 '4' */
    .byte 0xFC,0xC0,0xF8,0x0C,0x0C,0xCC,0x78,0x00   /* 0x35 '5' */
    .byte 0x38,0x60,0xC0,0xF8,0xCC,0xCC,0x78,0x00   /* 0x36 '6' */
    .byte 0xFC,0xCC,0x0C,0x18,0x30,0x30,0x30,0x00   /* 0x37 '7' */
    .byte 0x78,0xCC,0xCC,0x78,0xCC,0xCC,0x78,0x00   /* 0x38 '8' */
    .byte 0x78,0xCC,0xCC,0x7C,0x0C,0x18,0x70,0x00   /* 0x39 '9' */
    .byte 0x00,0x30,0x30,0x00,0x00,0x30,0x30,0x00   /* 0x3A ':' */
    .byte 0x00,0x30,0x30,0x00,0x00,0x30,0x30,0x60   /* 0x3B ';' */
    .byte 0x18,0x30,0x60,0xC0,0x60,0x30,0x18,0x00   /* 0x3C '<' */
    .byte 0x00,0x00,0xFC,0x00,0x00,0xFC,0x00,0x00   /* 0x3D '=' */
    .byte 0x60,0x30,0x18,0x0C,0x18,0x30,0x60,0x00   /* 0x3E '>' */
    .byte 0x78,0xCC,0x0C,0x18,0x30,0x00,0x30,0x00   /* 0x3F '?' */
    .byte 0x7C,0xC6,0xDE,0xDE,0xDE,0xC0,0x78,0x00   /* 0x40 '@' */
    .byte 0x30,0x78,0xCC,0xCC,0xFC,0xCC,0xCC,0x00   /* 0x41 'A' */
    .byte 0xFC,0x66,0x66,0x7C,0x66,0x66,0xFC,0x00   /* 0x42 'B' */
    .byte 0x3C,0x66,0xC0,0xC0,0xC0,0x66,0x3C,0x00   /* 0x43 'C' */
    .byte 0xF8,0x6C,0x66,0x66,0x66,0x6C,0xF8,0x00   /* 0x44 'D' */
    .byte 0xFE,0x62,0x68,0x78,0x68,0x62,0xFE,0x00   /* 0x45 'E' */
    .byte 0xFE,0x62,0x68,0x78,0x68,0x60,0xF0,0x00   /* 0x46 'F' */
    .byte 0x3C,0x66,0xC0,0xC0,0xCE,0x66,0x3E,0x00   /* 0x47 'G' */
    .byte 0xCC,0xCC,0xCC,0xFC,0xCC,0xCC,0xCC,0x00   /* 0x48 'H' */
    .byte 0x78,0x30,0x30,0x30,0x30,0x30,0x78,0x00   /* 0x49 'I' */
    .byte 0x1E,0x0C,0x0C,0x0C,0xCC,0xCC,0x78,0x00   /* 0x4A 'J' */
    .byte 0xE6,0x66,0x6C,0x78,0x6C,0x66,0xE6,0x00   /* 0x4B 'K' */
    .byte 0xF0,0x60,0x60,0x60,0x62,0x66,0xFE,0x00   /* 0x4C 'L' */
    .byte 0xC6,0xEE,0xFE,0xFE,0xD6,0xC6,0xC6,0x00   /* 0x4D 'M' */
    .byte 0xC6,0xE6,0xF6,0xDE,0xCE,0xC6,0xC6,0x00   /* 0x4E 'N' */
    .byte 0x38,0x6C,0xC6,0xC6,0xC6,0x6C,0x38,0x00   /* 0x4F 'O' */
    .byte 0xFC,0x66,0x66,0x7C,0x60,0x60,0xF0,0x00   /* 0x50 'P' */
    .byte 0x78,0xCC,0xCC,0xCC,0xDC,0x78,0x1C,0x00   /* 0x51 'Q' */
    .byte 0xFC,0x66,0x66,0x7C,0x6C,0x66,0xE6,0x00   /* 0x52 'R' */
    .byte 0x78,0xCC,0xE0,0x70,0x1C,0xCC,0x78,0x00   /* 0x53 'S' */
    .byte 0xFC,0xB4,0x30,0x30,0x30,0x30,0x78,0x00   /* 0x54 'T' */
    .byte 0xCC,0xCC,0xCC,0xCC,0xCC,0xCC,0xFC,0x00   /* 0x55 'U' */
    .byte 0xCC,0xCC,0xCC,0xCC,0xCC,0x78,0x30,0x00   /* 0x56 'V' */
    .byte 0xC6,0xC6,0xC6,0xD6,0xFE,0xEE,0xC6,0x00   /* 0x57 'W' */
    .byte 0xC6,0xC6,0x6C,0x38,0x38,0x6C,0xC6,0x00   /* 0x58 'X' */
    .byte 0xCC,0xCC,0xCC,0x78,0x30,0x30,0x78,0x00   /* 0x59 'Y' */
    .byte 0xFE,0xC6,0x8C,0x18,0x32,0x66,0xFE,0x00   /* 0x5A 'Z' */
    .byte 0x78,0x60,0x60,0x60,0x60,0x60,0x78,0x00   /* 0x5B '[' */
    .byte 0xC0,0x60,0x30,0x18,0x0C,0x06,0x02,0x00   /* 0x5C '\' */
    .byte 0x78,0x18,0x18,0x18,0x18,0x18,0x78,0x00   /* 0x5D ']' */
    .byte 0x10,0x38,0x6C,0xC6,0x00,0x00,0x00,0x00   /* 0x5E '^' */
    .byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xFF   /* 0x5F '_' */


_end:
