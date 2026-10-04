/* Marks final (all candidates): read the step-mark record and paint the
 * bands at every plausible display channel buffer, with G1 painted LAST so
 * its pattern is the final layer if several channels share a frame.
 *
 * History that shaped this build:
 *  - rch-probe2 (wide gate) showed a cyan fill -> one of the channels does
 *    point at the scanned buffer; g1-v1 (aperture gate) and g1-v2
 *    (>=0x1B00000 gate) both stayed dark -> G1's value lives in
 *    [1 MiB, 0x1B00000), i.e. low RAM right under the probe's own code.
 *  - 8 MiB fills from there would sweep through the running code (the
 *    marks-probe's mangled field and the old paint probe's silence),
 *    so the payload first copies itself to RELOC_DEST and continues there;
 *    the fills cannot touch the executing code any more.
 *  - The first relocation target (0x50000000) faulted instantly on device
 *    (early eRecovery) - not RAM there. RELOC_DEST = 0x31100000, inside
 *    the graphic carveout band that every probe's fallback fill has
 *    written without a fault.
 *
 * Readout: band 0..count = PAL[k%8] with k = band index; black above the
 * bands up to the fill length. count+1 bands = count step marks. 8 bands =
 * the kill build's record 123456F (7 marks).
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

/* fill FILL_LEN black at w20, then bands 0..count (w26) - only if w20 is in
 * [0x100000, 0xC0000000) and the range stays clear of the ramoops window.
 * BAND is 0x80000 = 1<<19: the band offset below is k<<19 and must track
 * the BAND defsym.
 * clobbers w13/w14/w15/w17/w18/w21/w22/w23/w24/w25/x9/x10 (never w26) */
.macro try_bands
    movz w13, #0x0010, lsl #16
    cmp  w20, w13
    b.lo 9f
    movz w13, #0xC000, lsl #16
    cmp  w20, w13
    b.hs 9f
    movz x15, #((FILL_LEN) >> 16), lsl #16
    movk x15, #((FILL_LEN) & 0xffff)
    add  w15, w15, w20
    /* sweep guard: refuse a fill whose range [w20, w15) would cross the
     * running code window [SAFE_LO, SAFE_HI). sized to FILL_LEN, so any
     * accepted fill stops at or above SAFE_HI: no self-clobber, ever. */
    movz w17, #((SAFE_LO) >> 16), lsl #16
    movk w17, #((SAFE_LO) & 0xffff)
    movz w18, #((SAFE_HI) >> 16), lsl #16
    movk w18, #((SAFE_HI) & 0xffff)
    cmp  w20, w18
    b.hs 60f
    cmp  w15, w17
    b.ls 60f
    b    9f
60:
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
    add  w24, w20, w22, lsl #18         /* BAND is 0x40000: k*BAND = k<<18 */
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
    /* QEMU: plant the marks record and a G1 slot value to exercise the paint */
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
.endif

    /* No relocation: the fill window guard below makes running from the
     * normal load address safe. FILL_LEN is deliberately small (4 MiB, the
     * size that survived in rch-probe2) and any fill whose range would
     * sweep the code run below is refused outright. */

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
    /* --- the marks bands at every candidate (G1 last: final layer) --- */
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

    /* G1 last: strongest candidate for the scanned frame - its pattern wins
     * any overlap with the others */
    movz w19, #((RCH_G1_BASE) >> 16), lsl #16
    movk w19, #((RCH_G1_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    try_bands

    spin SPIN_HOLD, HOLD_REPEATS

    /* stay: the bands are the readout, so keep them on screen */
.Lhang:
    wfe
    b    .Lhang

_end:
