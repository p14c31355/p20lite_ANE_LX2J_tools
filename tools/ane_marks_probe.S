/* Marks probe: read the step-mark scratch and paint the record as bands on
 * the buffer the display actually scans.
 *
 * This is the readout half of the early-vector kill proof. rch-probe2 showed
 * that a fill into one of the ten DMA-bearing DSS channels' DATA_ADDR0
 * targets is VISIBLE on the panel (cyan-family block over the loader menu) -
 * the first visible paint of the campaign. This probe paints the actual
 * record there: a black canvas, then band 0 white, then one band per step
 * mark (colour PAL[k % 8] = white, green, blue, yellow, cyan, magenta, red,
 * orange). Counting the bands on a photo yields the mark count: the
 * expected record after the kill build is 123456F = 7 marks = 8 bands.
 *
 * Candidate set = the rch-probe2 set (the ten channels' DATA_ADDR0 at +0x60)
 * plus the fixed fallback; every plausible one gets the same band pattern,
 * so no channel identification is needed for the readout. The ramoops
 * window [0x34800000, 0x34900000) is protected from every fill. Then the
 * hang: the bands stay on screen until the loader's watchdog fallback.
 *
 * Register facts (vendor tree,
 * drivers/hisi/ap/platform/hi6250/soc_dss_interface.h): channel DMA offsets
 * VG0 0x20000 / VG1 0x28000 / G0 0x38000 / G1 0x40000 / D0 0x50000 /
 * D1 0x51000 / D2 0x52000 / D3 0x53000 / WCH0 0x5A000 / WCH1 0x5C000, and
 * DMA_DATA_ADDR0 = 0x0060 (the source framebuffer address).
 *
 * Build variants via --defsym: the device uses the real DSS bases and the
 * real scratch; the QEMU check points the bases at RAM (reads return zero ->
 * all channels skipped) and the scratch at RAM with WITH_SEED planting a
 * fake record, so the band painting runs on the fallback with known input.
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

/* paint band \idx colour into w21; clobbers w21 only */
.macro setcolor idx
    movz w21, #0xFFFF
    movk w21, #0xFFFF, lsl #16          /* 0 white   0xFFFFFFFF */
    cmp  \idx, #0
    b.eq 77f
    movz w21, #0xFF00
    movk w21, #0xFF00, lsl #16          /* 1 green   0xFF00FF00 */
    cmp  \idx, #1
    b.eq 77f
    movz w21, #0x0000
    movk w21, #0xFFFF, lsl #16          /* 2 blue    0xFFFF0000 */
    cmp  \idx, #2
    b.eq 77f
    movz w21, #0xFFFF
    movk w21, #0xFF00, lsl #16          /* 3 yellow  0xFF00FFFF */
    cmp  \idx, #3
    b.eq 77f
    movz w21, #0xFF00
    movk w21, #0xFFFF, lsl #16          /* 4 cyan    0xFFFFFF00 */
    cmp  \idx, #4
    b.eq 77f
    movz w21, #0x00FF
    movk w21, #0xFFFF, lsl #16          /* 5 magenta 0xFFFF00FF */
    cmp  \idx, #5
    b.eq 77f
    movz w21, #0x00FF
    movk w21, #0xFF00, lsl #16          /* 6 red     0xFF0000FF */
    cmp  \idx, #6
    b.eq 77f
    movz w21, #0x80FF
    movk w21, #0xFF00, lsl #16          /* 7 orange  0xFF0080FF */
77:
.endm

/* fill FILL_LEN black at w20, then bands 0..count (w26) - only if w20 is
 * plausible RAM and the range stays clear of the ramoops window.
 * BAND is 0x80000 = 1<<19: the band offset below is k<<19 and must track
 * the BAND defsym in the build scripts (both builds use the same value).
 * clobbers w13/w14/w15/w17/w18/w21/w22/w23/w24/w25/x9/x10 (never w26) */
.macro try_bands
    cmp  w20, #0x00100000
    b.lo 9f
    movz w13, #0xC000, lsl #16
    cmp  w20, w13
    b.hs 9f
    movz x15, #((FILL_LEN) >> 16), lsl #16
    movk x15, #((FILL_LEN) & 0xffff)
    add  w15, w15, w20
    movz w17, #((RAMO_WIN_START) >> 16), lsl #16
    movk w17, #((RAMO_WIN_START) & 0xffff)
    movz w18, #((RAMO_WIN_END) >> 16), lsl #16
    movk w18, #((RAMO_WIN_END) & 0xffff)
    cmp  w15, w17
    b.ls 6f
    cmp  w20, w18
    b.hs 6f
    b    9f
6:
    mov  w14, w20
    movz x9, #((FILL_LEN) >> 16), lsl #16
    movk x9, #((FILL_LEN) & 0xffff)
    add  x9, x9, x14
    movz w10, #0x0000
    movk w10, #0xFF00, lsl #16          /* opaque black 0xFF000000 */
    orr  x10, x10, x10, lsl #32
1:  stp  x10, x10, [x14], #16
    cmp  x14, x9
    b.lo 1b
    mov  w22, #0
2:  and  w23, w22, #7
    setcolor w23
    add  w24, w20, w22, lsl #19         /* BAND is 0x80000: k*BAND = k<<19 */
    mov  w14, w24
    movz w25, #((BAND) >> 16), lsl #16
    movk w25, #((BAND) & 0xffff)
    add  w25, w24, w25
    orr  x10, x21, x21, lsl #32
3:  stp  x10, x10, [x14], #16
    cmp  w14, w25
    b.lo 3b
    add  w22, w22, #1
    cmp  w22, w26
    b.le 2b
9:
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
    /* QEMU proof only: plant a fake marks record ("ANEM", 3, "123") so the
       band logic has known input without any earlier boot. */
    movz x27, #((MARKS_BASE) >> 16), lsl #16
    movk x27, #((MARKS_BASE) & 0xffff)
    movz w10, #0x4E41
    movk w10, #0x4D45, lsl #16          /* "ANEM" */
    str  w10, [x27]
    mov  w10, #3
    str  w10, [x27, #4]
    movz w10, #0x3231                   /* '1','2' */
    movk w10, #0x0033, lsl #16          /* '3' */
    str  w10, [x27, #8]
.endif

    /* --- read the marks record; count lands in w26 (0 when absent) --- */
    movz x27, #((MARKS_BASE) >> 16), lsl #16
    movk x27, #((MARKS_BASE) & 0xffff)
    ldr  w24, [x27]
    movz w25, #0x4E41
    movk w25, #0x4D45, lsl #16
    cmp  w24, w25
    b.ne .Lnostamp
    ldr  w26, [x27, #4]
    cmp  w26, #15
    b.ls .Lhave
    mov  w26, #15
    b    .Lhave
.Lnostamp:
    mov  w26, #0

.Lhave:
    /* --- the marks bands at every candidate --- */
    movz w19, #((RCH_VG0_BASE) >> 16), lsl #16
    movk w19, #((RCH_VG0_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    try_bands

    movz w19, #((RCH_VG1_BASE) >> 16), lsl #16
    movk w19, #((RCH_VG1_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    try_bands

    movz w19, #((RCH_G0_BASE) >> 16), lsl #16
    movk w19, #((RCH_G0_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    try_bands

    movz w19, #((RCH_G1_BASE) >> 16), lsl #16
    movk w19, #((RCH_G1_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    try_bands

    movz w19, #((RCH_D0_BASE) >> 16), lsl #16
    movk w19, #((RCH_D0_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    try_bands

    movz w19, #((RCH_D1_BASE) >> 16), lsl #16
    movk w19, #((RCH_D1_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    try_bands

    movz w19, #((RCH_D2_BASE) >> 16), lsl #16
    movk w19, #((RCH_D2_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    try_bands

    movz w19, #((RCH_D3_BASE) >> 16), lsl #16
    movk w19, #((RCH_D3_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    try_bands

    movz w19, #((RCH_WCH0_BASE) >> 16), lsl #16
    movk w19, #((RCH_WCH0_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    try_bands

    movz w19, #((RCH_WCH1_BASE) >> 16), lsl #16
    movk w19, #((RCH_WCH1_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    try_bands

    /* fixed fallback (the kernel's reserved graphic region) */
    movz w20, #((FALLBACK_BASE) >> 16), lsl #16
    movk w20, #((FALLBACK_BASE) & 0xffff)
    try_bands

    spin SPIN_HOLD, HOLD_REPEATS

.if WITH_SMC
    movz w0, #0x0009
    movk w0, #0x8400, lsl #16
    mov  x1, xzr
    mov  x2, xzr
    mov  x3, xzr
    smc  #0
.endif

    /* stay: the bands are the readout, so keep them on screen */
.Lhang:
    wfe
    b    .Lhang
