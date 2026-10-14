/* Framebuffer probe for the ANE-LX2J: a signal the eye can read directly.
 *
 * The USB probe produced no host-visible events, which leaves three live
 * explanations (not entered / MMIO or clocks dead / writes never landed). The
 * framebuffer cuts the knot: the loader itself draws the boot logo into
 * 0x31000000 (its DT node is /reserved-memory/graphic, 0x1a40000 bytes), so if
 * the loader's page tables are live at handoff - the case that would explain
 * silent MMIO elsewhere - this region is still mapped, and the display
 * controller is already scanning it.
 *
 * So: fill the whole region with one saturated colour and stop. Readout:
 *   screen turns solid colour      -> the loader entered our code AND RAM writes
 *                                     land AND the display is still scanning
 *   colour, then the logo repeats  -> same, and the SMC reset also works
 *   nothing at all                 -> the loader is not entering our code
 *                                     (the loading contract is the problem)
 *
 * The fill covers the whole region because the internal layout (stride, buffer
 * count) is not in the tree; whatever buffer is being scanned gets covered.
 * Addresses: /reserved-memory/graphic reg = <0x31000000 0x1a40000> in the
 * handset's own device tree dump (firmware/ane_dtb/fdt_properties.txt).
 */

.section .text, "ax"
.balign 4
.global _start

/* busy-wait: w11 counts down, then w12 repeats; clobbers w11, w12, flags */
.macro spin count, repeats=1
    movz w12, #((\repeats) & 0xffff)
1:  movz w11, #((\count >> 16) & 0xffff)
    movk w11, #((\count >> 32) & 0xffff), lsl #16
2:  subs w11, w11, #1
    b.ne 2b
    subs w12, w12, #1
    b.ne 1b
.endm

_start:
    /* end address = FB_BASE + FB_SIZE */
    movz x11, #(((FB_BASE + FB_SIZE)) >> 16), lsl #16
    movk x11, #(((FB_BASE + FB_SIZE)) & 0xffff)

    /* 64-bit fill word = the colour duplicated */
    movz w10, #((COLOR) & 0xffff)
    movk w10, #(((COLOR) >> 16) & 0xffff), lsl #16
    orr  x10, x10, x10, lsl #32

    movz x9, #((FB_BASE) >> 16), lsl #16
    movk x9, #((FB_BASE) & 0xffff)
1:  stp  x10, x10, [x9], #16
    cmp  x9, x11
    b.lo 1b

    /* hold so the colour is unmistakable, then try the reset: if the loader
     * entered us, the machine reboots and this probe replays - colour, logo,
     * colour - a pattern nobody can miss. */
    spin SPIN_HOLD, HOLD_REPEATS

.if WITH_SMC
    movz w0, #0x0009
    movk w0, #0x8400, lsl #16
    mov  x1, xzr
    mov  x2, xzr
    mov  x3, xzr
    smc  #0
.endif

    /* if the reset did not happen, stop here with the colour on screen */
.Lhang:
    wfe
    b    .Lhang
