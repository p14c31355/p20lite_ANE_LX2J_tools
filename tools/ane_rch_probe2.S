/* RCH probe v2: find the buffer the display actually scans, across every
 * DMA-bearing channel, and colour each plausible one.
 *
 * v1 read only the four overlay read channels (VG0/VG1/G0/G1). The loader's
 * own display path need not go through the overlay: the write channels
 * (WCH0/WCH1) and the direct channels (D0..D3) each have their own DMA block
 * with a DATA_ADDR0 (+0x60) source address, and one of them is at least as
 * likely to hold the live framebuffer. All ten are read here; the colour
 * that appears on screen names which channel's buffer the panel scans.
 *
 * Register facts (vendor tree,
 * drivers/hisi/ap/platform/hi6250/soc_dss_interface.h):
 *   DSS_BASE = 0xE8600000
 *   DSS_RCH_VG0_DMA_OFFSET = 0x20000 -> 0xE8620000
 *   DSS_RCH_VG1_DMA_OFFSET = 0x28000 -> 0xE8628000
 *   DSS_RCH_G0_DMA_OFFSET  = 0x38000 -> 0xE8638000
 *   DSS_RCH_G1_DMA_OFFSET  = 0x40000 -> 0xE8640000
 *   DSS_RCH_D0_DMA_OFFSET  = 0x50000 -> 0xE8650000
 *   DSS_RCH_D1_DMA_OFFSET  = 0x51000 -> 0xE8651000
 *   DSS_RCH_D2_DMA_OFFSET  = 0x52000 -> 0xE8652000
 *   DSS_RCH_D3_DMA_OFFSET  = 0x53000 -> 0xE8653000
 *   DSS_WCH0_DMA_OFFSET    = 0x5A000 -> 0xE865A000
 *   DSS_WCH1_DMA_OFFSET    = 0x5C000 -> 0xE865C000
 *   DMA_DATA_ADDR0 = 0x0060 (the source framebuffer address)
 *
 * Fill order matters: fills run channel by channel, so when several
 * channels point at one buffer the last plausible one wins - the order
 * below ends with the write channels, the most likely source for the
 * loader's own framebuffer. The fixed fallback (the kernel's reserved
 * graphic region) gets magenta last. The ramoops window is protected: a
 * fill whose range would reach into it is skipped, so the step-mark
 * scratch and the black box survive the sweep. Then the spin holds the
 * screen until the loader's watchdog fallback.
 *
 * Build variants via --defsym: the device uses the real DSS bases, the QEMU
 * check points the same code at RAM so its reads return zero (implausible)
 * and only the fallback fill runs - which is exactly the logic under test.
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

/* fill FILL_LEN bytes at w20 with the colour in w21, if w20 looks like RAM
 * and the range does not reach into the protected ramoops window
 * [RAMO_WIN_START, RAMO_WIN_END) */
.macro try_fill
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
    orr  x10, x21, x21, lsl #32
    mov  w14, w20
    movz x9, #((FILL_LEN) >> 16), lsl #16
    movk x9, #((FILL_LEN) & 0xffff)
    add  x9, x9, x14
1:  stp  x10, x10, [x14], #16
    cmp  x14, x9
    b.lo 1b
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

    /* VG0 -> green  (ABGR 0xFF00FF00) */
    movz w19, #((RCH_VG0_BASE) >> 16), lsl #16
    movk w19, #((RCH_VG0_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    movz w21, #0xFF00
    movk w21, #0xFF00, lsl #16
    try_fill

    /* VG1 -> blue   (ABGR 0xFFFF0000) */
    movz w19, #((RCH_VG1_BASE) >> 16), lsl #16
    movk w19, #((RCH_VG1_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    movz w21, #0x0000
    movk w21, #0xFFFF, lsl #16
    try_fill

    /* G0 -> red     (ABGR 0xFF0000FF) */
    movz w19, #((RCH_G0_BASE) >> 16), lsl #16
    movk w19, #((RCH_G0_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    movz w21, #0x00FF
    movk w21, #0xFF00, lsl #16
    try_fill

    /* G1 -> cyan    (ABGR 0xFFFFFF00) */
    movz w19, #((RCH_G1_BASE) >> 16), lsl #16
    movk w19, #((RCH_G1_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    movz w21, #0xFF00
    movk w21, #0xFFFF, lsl #16
    try_fill

    /* D0 -> yellow  (ABGR 0xFF00FFFF) */
    movz w19, #((RCH_D0_BASE) >> 16), lsl #16
    movk w19, #((RCH_D0_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    movz w21, #0xFFFF
    movk w21, #0xFF00, lsl #16
    try_fill

    /* D1 -> orange  (ABGR 0xFF00A5FF) */
    movz w19, #((RCH_D1_BASE) >> 16), lsl #16
    movk w19, #((RCH_D1_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    movz w21, #0xA5FF
    movk w21, #0xFF00, lsl #16
    try_fill

    /* D2 -> white   (ABGR 0xFFFFFFFF) */
    movz w19, #((RCH_D2_BASE) >> 16), lsl #16
    movk w19, #((RCH_D2_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    movz w21, #0xFFFF
    movk w21, #0xFFFF, lsl #16
    try_fill

    /* D3 -> purple  (ABGR 0xFFFF0080) */
    movz w19, #((RCH_D3_BASE) >> 16), lsl #16
    movk w19, #((RCH_D3_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    movz w21, #0x0080
    movk w21, #0xFFFF, lsl #16
    try_fill

    /* WCH0 -> teal  (ABGR 0xFF808000) */
    movz w19, #((RCH_WCH0_BASE) >> 16), lsl #16
    movk w19, #((RCH_WCH0_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    movz w21, #0x8000
    movk w21, #0xFF80, lsl #16
    try_fill

    /* WCH1 -> pink  (ABGR 0xFFB469FF) */
    movz w19, #((RCH_WCH1_BASE) >> 16), lsl #16
    movk w19, #((RCH_WCH1_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    movz w21, #0x69FF
    movk w21, #0xFFB4, lsl #16
    try_fill

    /* fixed fallback (the kernel's reserved graphic region) -> magenta
     * (ABGR 0xFFFF00FF) */
    movz w20, #((FALLBACK_BASE) >> 16), lsl #16
    movk w20, #((FALLBACK_BASE) & 0xffff)
    movz w21, #0x00FF
    movk w21, #0xFFFF, lsl #16
    try_fill

    spin SPIN_HOLD, HOLD_REPEATS

.if WITH_SMC
    movz w0, #0x0009
    movk w0, #0x8400, lsl #16
    mov  x1, xzr
    mov  x2, xzr
    mov  x3, xzr
    smc  #0
.endif

.Lhang:
    wfe
    b    .Lhang
