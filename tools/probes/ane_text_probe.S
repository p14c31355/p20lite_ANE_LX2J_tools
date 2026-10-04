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
.endif

    /* ---- build the text string at TEXT_BUF ---- */
    movz x28, #((TEXT_BUF) >> 16), lsl #16
    movk x28, #((TEXT_BUF) & 0xffff)

    /* ten value entries, two per line: "Vn XXXXXXXX Vn XXXXXXXX" + pad */
    mov  w2, #0
9:  mov  w21, #0x56                   /* 'V' */
    strb w21, [x28], #1
    mov  w21, w2
    add  w21, w21, #0x30               /* '0'+n (single digit) */
    strb w21, [x28], #1
    mov  w21, #0x20                    /* ' ' */
    strb w21, [x28], #1
    /* value n from its channel base */
    movz w19, #((RCH_VG0_BASE) >> 16), lsl #16
    movk w19, #((RCH_VG0_BASE) & 0xffff)
    cbz  w2, 11f
    movz w19, #((RCH_VG1_BASE) >> 16), lsl #16
    movk w19, #((RCH_VG1_BASE) & 0xffff)
    cmp  w2, #1
    b.eq 11f
    movz w19, #((RCH_G0_BASE) >> 16), lsl #16
    movk w19, #((RCH_G0_BASE) & 0xffff)
    cmp  w2, #2
    b.eq 11f
    movz w19, #((RCH_G1_BASE) >> 16), lsl #16
    movk w19, #((RCH_G1_BASE) & 0xffff)
    cmp  w2, #3
    b.eq 11f
    movz w19, #((RCH_D0_BASE) >> 16), lsl #16
    movk w19, #((RCH_D0_BASE) & 0xffff)
    cmp  w2, #4
    b.eq 11f
    movz w19, #((RCH_D1_BASE) >> 16), lsl #16
    movk w19, #((RCH_D1_BASE) & 0xffff)
    cmp  w2, #5
    b.eq 11f
    movz w19, #((RCH_D2_BASE) >> 16), lsl #16
    movk w19, #((RCH_D2_BASE) & 0xffff)
    cmp  w2, #6
    b.eq 11f
    movz w19, #((RCH_D3_BASE) >> 16), lsl #16
    movk w19, #((RCH_D3_BASE) & 0xffff)
    cmp  w2, #7
    b.eq 11f
    movz w19, #((RCH_WCH0_BASE) >> 16), lsl #16
    movk w19, #((RCH_WCH0_BASE) & 0xffff)
    cmp  w2, #8
    b.eq 11f
    movz w19, #((RCH_WCH1_BASE) >> 16), lsl #16
    movk w19, #((RCH_WCH1_BASE) & 0xffff)
11: /* three slots on one line: +0x60, +0x84, +0xA8 (36 = 0x24 step) */
    mov  w4, #0
10: lsl  w5, w4, #2
    add  w5, w5, w4, lsl #5            /* slot*36 */
    add  w5, w5, #0x60
    ldr  w25, [x19, w5, uxtw]
    mov  w23, #28
12: lsr  w21, w25, w23
    nib2asc
    strb w21, [x28], #1
    subs w23, w23, #4
    b.ge 12b
    add  w4, w4, #1
    cmp  w4, #3
    b.ne 10b
    mov  w23, #6                       /* pad: 3 + 24 + 6 = 33 */
16: mov  w21, #0x20
    strb w21, [x28], #1
    subs w23, w23, #1
    b.ne 16b
15: add  w2, w2, #1
    cmp  w2, #10
    b.ne 9b

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
    mov  w23, #6
20: mov  w21, #0x20
    strb w21, [x28], #1
    subs w23, w23, #1
    b.ne 20b
    b    17b                           /* continue with bytes 12..23 */
19: mov  w23, #9
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

    /* ---- render 6x33 glyphs into the bitmap (cyan, 4x scale) ---- */
    movz x2, #((TEXT_BUF) >> 16), lsl #16
    movk x2, #((TEXT_BUF) & 0xffff)
    movz x12, #0xFF00
    movk x12, #0xFFFF, lsl #16         /* cyan 0xFFFFFF00 */
    orr  x12, x12, x12, lsl #32
    movz w13, #0x10E0                  /* screen row stride 4320 */
    mov  w4, #0                       /* line 0..5 */
23: mov  w5, #0                       /* col 0..32 */
24: ldrb w6, [x2], #1                 /* char */
    /* map char -> glyph index w7 */
    mov  w7, #19                       /* ' ' / unknown */
    cmp  w6, #0x30
    b.lo 25f
    cmp  w6, #0x39
    b.hi 26f
    sub  w7, w6, #0x30
    b    25f
26: cmp  w6, #0x41
    b.lo 27f
    cmp  w6, #0x46
    b.hi 27f
    sub  w7, w6, #0x41
    add  w7, w7, #10
    b    25f
27: cmp  w6, #0x56                   /* 'V' */
    b.ne 28f
    mov  w7, #16
    b    25f
28: cmp  w6, #0x52                   /* 'R' */
    b.ne 25f
    mov  w7, #17
25: /* glyph cell top-left pixel (x = 16 + col*32, y = 16 + line*40) */
    lsl  w8, w4, #3                    /* line*8 */
    add  w8, w8, w4, lsl #5            /* + line*32 = line*40 */
    add  w8, w8, #16
    movz w9, #((BITMAP) >> 16), lsl #16
    movk w9, #((BITMAP) & 0xffff)
    mul  w8, w8, w13                   /* y*4320 */
    add  x8, x9, w8, uxtw
    lsl  w10, w5, #5                   /* col*32 */
    add  w10, w10, #16
    lsl  w10, w10, #2                  /* (16+col*32)*4 */
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
    lsl  w17, w16, #4                  /* gx*16 */
    add  x18, x8, w17, uxtw
    stp  x12, x12, [x18]
    add  x18, x18, x13
    stp  x12, x12, [x18]
    add  x18, x18, x13
    stp  x12, x12, [x18]
    add  x18, x18, x13
    stp  x12, x12, [x18]
31: lsl  w15, w15, #1
    add  w16, w16, #1
    cmp  w16, #8
    b.ne 30b
    add  x8, x8, x13
    add  x8, x8, x13
    add  x8, x8, x13
    add  x8, x8, x13                   /* next glyph row: +4 scanlines */
    add  w14, w14, #1
    cmp  w14, #8
    b.ne 29b
    add  w5, w5, #1
    cmp  w5, #33
    b.ne 24b
    add  w4, w4, #1
    cmp  w4, #12
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
    .byte 0x3C,0x66,0x6E,0x76,0x66,0x66,0x3C,0x00   /* 0 */
    .byte 0x18,0x38,0x18,0x18,0x18,0x18,0x7E,0x00   /* 1 */
    .byte 0x3C,0x66,0x06,0x0C,0x18,0x30,0x7E,0x00   /* 2 */
    .byte 0x3C,0x66,0x06,0x1C,0x06,0x66,0x3C,0x00   /* 3 */
    .byte 0x0C,0x1C,0x3C,0x6C,0x7E,0x0C,0x0C,0x00   /* 4 */
    .byte 0x7E,0x60,0x7C,0x06,0x06,0x66,0x3C,0x00   /* 5 */
    .byte 0x1C,0x30,0x60,0x7C,0x66,0x66,0x3C,0x00   /* 6 */
    .byte 0x7E,0x66,0x06,0x0C,0x18,0x18,0x18,0x00   /* 7 */
    .byte 0x3C,0x66,0x66,0x3C,0x66,0x66,0x3C,0x00   /* 8 */
    .byte 0x3C,0x66,0x66,0x3E,0x06,0x0C,0x38,0x00   /* 9 */
    .byte 0x18,0x3C,0x66,0x66,0x7E,0x66,0x66,0x00   /* A */
    .byte 0x7C,0x66,0x66,0x7C,0x66,0x66,0x7C,0x00   /* B */
    .byte 0x3C,0x66,0x60,0x60,0x60,0x66,0x3C,0x00   /* C */
    .byte 0x78,0x6C,0x66,0x66,0x66,0x6C,0x78,0x00   /* D */
    .byte 0x7E,0x60,0x60,0x7C,0x60,0x60,0x7E,0x00   /* E */
    .byte 0x7E,0x60,0x60,0x7C,0x60,0x60,0x60,0x00   /* F */
    .byte 0x66,0x66,0x66,0x66,0x66,0x66,0x3C,0x00   /* V */
    .byte 0x7C,0x66,0x66,0x7C,0x6C,0x66,0x66,0x00   /* R */
    .byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00   /* space */

_end:
