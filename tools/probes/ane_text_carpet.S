/* Text carpet: stamp the text bitmap across a whole address range.
 *
 * Every targeted probe so far missed the scanner: rch-probe2's cyan fill
 * proved SOMETHING in a low window is scanned, but reads of the display
 * channels' DMA registers never pinned the address, and each guarded
 * variant excluded a different window. This probe stops guessing and
 * carpets the range [0x01000000, 0x30000000) with the text bitmap stamped
 * every 0x210000 (2.16 MiB, its own size), skipping only the code island
 * [ISLAND_LO, ISLAND_HI) - the payload, text buffer and bitmap themselves.
 * The scanner, wherever its base sits in the range, sees the text within
 * one stamp of its position, near the top of its window.
 *
 * The fills never overlap the running code (two disjoint safe spans:
 * below the island and above it), so no self-clobber is possible, and the
 * ramoops window sits outside the range entirely.
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

/* blit the bitmap to the address in x20, clipped at the island: a stamp
 * starting below the island paints only up to ISLAND_LO (never touches the
 * code); a stamp inside the island is skipped; above it runs full length.
 * clobbers w9-w11/x9-w13; x20 preserved */
.macro carpet_blit
    movz w9, #((ISLAND_LO) >> 16), lsl #16
    movk w9, #((ISLAND_LO) & 0xffff)
    cmp  w20, w9
    b.lo 88f
    movz w9, #((ISLAND_HI) >> 16), lsl #16
    movk w9, #((ISLAND_HI) & 0xffff)
    cmp  w20, w9
    b.hs 87f
    b    89f                          /* inside the island: skip */
88: /* below: length = ISLAND_LO - v */
    movz w11, #((ISLAND_LO) >> 16), lsl #16
    movk w11, #((ISLAND_LO) & 0xffff)
    sub  w11, w11, w20
    b    86f
87: /* above: full length */
    movz w11, #((BITMAP_LEN) >> 16), lsl #16
    movk w11, #((BITMAP_LEN) & 0xffff)
86: movz x9, #((BITMAP) >> 16), lsl #16
    movk x9, #((BITMAP) & 0xffff)
    add  x11, x9, w11, uxtw
    add  x10, x20, xzr
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

    /* ---- build the text string at TEXT_BUF (same content as ane_text_probe) ---- */
    movz x28, #((TEXT_BUF) >> 16), lsl #16
    movk x28, #((TEXT_BUF) & 0xffff)

    mov  w2, #0
9:  mov  w21, #0x56                   /* 'V' */
    strb w21, [x28], #1
    mov  w21, w2
    add  w21, w21, #0x30
    strb w21, [x28], #1
    mov  w21, #0x20
    strb w21, [x28], #1
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
11: mov  w4, #0
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
    mov  w23, #6
16: mov  w21, #0x20
    strb w21, [x28], #1
    subs w23, w23, #1
    b.ne 16b
15: add  w2, w2, #1
    cmp  w2, #10
    b.ne 9b

    /* record lines */
    mov  w21, #0x52
    strb w21, [x28], #1
    mov  w21, #0x43
    strb w21, [x28], #1
    mov  w21, #0x20
    strb w21, [x28], #1
    movz x27, #((MARKS_BASE) >> 16), lsl #16
    movk x27, #((MARKS_BASE) & 0xffff)
    mov  w24, #0
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
18: cmp  w24, #12
    b.ne 19f
    mov  w23, #6
20: mov  w21, #0x20
    strb w21, [x28], #1
    subs w23, w23, #1
    b.ne 20b
    b    17b
19: mov  w23, #9
21: mov  w21, #0x20
    strb w21, [x28], #1
    subs w23, w23, #1
    b.ne 21b

    /* ---- clear the bitmap to black ---- */
    movz x9, #((BITMAP) >> 16), lsl #16
    movk x9, #((BITMAP) & 0xffff)
    movz x10, #0x0000
    movk x10, #0xFF00, lsl #16
    orr  x10, x10, x10, lsl #32
    movz x11, #((BITMAP_LEN) >> 16), lsl #16
    movk x11, #((BITMAP_LEN) & 0xffff)
    add  x11, x11, x9
22: stp  x10, x10, [x9], #16
    cmp  x9, x11
    b.lo 22b

    /* ---- render 12x33 glyphs into the bitmap (cyan, 4x) ---- */
    movz x2, #((TEXT_BUF) >> 16), lsl #16
    movk x2, #((TEXT_BUF) & 0xffff)
    movz x12, #0xFF00
    movk x12, #0xFFFF, lsl #16
    orr  x12, x12, x12, lsl #32
    movz w13, #0x10E0
    mov  w4, #0
23: mov  w5, #0
24: ldrb w6, [x2], #1
    mov  w7, #19
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
27: cmp  w6, #0x56
    b.ne 28f
    mov  w7, #16
    b    25f
28: cmp  w6, #0x52
    b.ne 25f
    mov  w7, #17
25: lsl  w8, w4, #3
    add  w8, w8, w4, lsl #5
    add  w8, w8, #16
    movz w9, #((BITMAP) >> 16), lsl #16
    movk w9, #((BITMAP) & 0xffff)
    mul  w8, w8, w13
    add  x8, x9, w8, uxtw
    lsl  w10, w5, #5
    add  w10, w10, #16
    lsl  w10, w10, #2
    add  x8, x8, w10, uxtw
    adr  x9, FONT
    lsl  x7, x7, #3
    add  x9, x9, x7
    mov  w14, #0
29: ldrb w15, [x9], #1
    mov  w16, #0
30: tst  w15, #0x80
    b.eq 31f
    lsl  w17, w16, #4
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
    add  x8, x8, x13
    add  w14, w14, #1
    cmp  w14, #8
    b.ne 29b
    add  w5, w5, #1
    cmp  w5, #33
    b.ne 24b
    add  w4, w4, #1
    cmp  w4, #12
    b.ne 23b

    /* ---- carpet: stamp the bitmap across [CARPET_LO, CARPET_HI) ---- */
    movz x20, #((CARPET_LO) >> 16), lsl #16
    movk x20, #((CARPET_LO) & 0xffff)
61: movz x9, #((CARPET_HI) >> 16), lsl #16
    movk x9, #((CARPET_HI) & 0xffff)
    cmp  x20, x9
    b.hs 62f
    carpet_blit
    movz w10, #((STAMP_STEP) >> 16), lsl #16
    movk w10, #((STAMP_STEP) & 0xffff)
    add  x20, x20, x10
    b    61b
62:

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
