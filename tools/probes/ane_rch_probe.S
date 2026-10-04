/* RCH probe: find the buffer the display is actually scanning, and colour it.
 *
 * The fb2 probe proved our code runs (its PSCI reset produced a visible reset
 * loop) but its fill of the kernel's reserved graphic region never appeared -
 * so the panel is not scanning that region in the handoff state. The DSS says
 * where it reads from: each read channel (RCH) has a DMA block whose
 * DATA_ADDR0 register (+0x60) holds the source framebuffer address.
 *
 * Register facts (vendor tree, drivers/hisi/ap/platform/hi6250):
 *   DSS_BASE = 0xE8600000
 *   DSS_RCH_VG0_DMA_OFFSET = 0x20000 -> 0xE8620000   DATA_ADDR0 = +0x60
 *   DSS_RCH_VG1_DMA_OFFSET = 0x28000 -> 0xE8628000
 *   DSS_RCH_G0_DMA_OFFSET  = 0x38000 -> 0xE8638000
 *   DSS_RCH_G1_DMA_OFFSET  = 0x40000 -> 0xE8640000
 *
 * Read all four; for each address that plausibly is RAM (>=1 MiB, <0xC0000000,
 * i.e. below the peripheral window that holds the DSS itself) fill FILL_LEN
 * bytes from it with a distinct colour. The colour that appears on screen
 * names the channel - one run reports which buffer the panel scans, with no
 * data formatting needed. The fixed fallback region gets magenta last. Then
 * the PSCI reset loops the whole sequence.
 *
 * Build variants via --defsym: the device uses the real DSS base, the QEMU
 * check points the same code at RAM so its reads return zero (implausible) and
 * only the fallback fill runs - which is exactly the logic under test.
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

/* fill FILL_LEN bytes at w20 with the colour in w21, if w20 looks like RAM */
.macro try_fill
    cmp  w20, #0x00100000
    b.lo 9f
    movz w13, #0xC000, lsl #16
    cmp  w20, w13
    b.hs 9f
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
