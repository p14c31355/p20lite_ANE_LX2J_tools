/* Framebuffer probe v2: same readout as the first, with the one addition the
 * evidence now demands - the MMU is turned OFF if the loader left it on.
 *
 * Every channel so far was silent (pstore zones, USB DCTL, framebuffer fill).
 * One explanation covers all three: the loader jumps with its MMU still
 * enabled, its page tables do not cover the regions a kernel is supposed to
 * touch at handoff, and our first access faults before anything is written.
 * The stock kernel would survive that handoff because it builds its own tables
 * before touching reserved memory; a probe that stores immediately does not.
 *
 * So: read CurrentEL, and if the current EL's SCTLR has M set, clear it and
 * ISB. Then everything below runs with identity physical addressing, and the
 * fill/store path is exactly the one QEMU already verified.
 *
 * Timing note: with the MMU off, data accesses are non-cacheable, so the fill
 * reaches DRAM directly and the display controller (a DMA reader) sees it.
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

_start:
    /* --- MMU-off preamble: only touch the current EL's SCTLR --- */
    mrs  x0, CurrentEL
    cmp  x0, #0x4                   /* EL1? */
    b.eq 1f
    cmp  x0, #0x8                   /* EL2? */
    b.eq 2f
    b    3f                         /* other ELs: leave alone (safe path) */
1:  mrs  x1, sctlr_el1
    tbnz x1, #0, 4f                 /* M set -> clear it */
    b    3f                         /* already off */
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

    /* --- the verified fill: whole graphic region, one colour --- */
    movz x11, #(((FB_BASE + FB_SIZE)) >> 16), lsl #16
    movk x11, #(((FB_BASE + FB_SIZE)) & 0xffff)
    movz w10, #((COLOR) & 0xffff)
    movk w10, #(((COLOR) >> 16) & 0xffff), lsl #16
    orr  x10, x10, x10, lsl #32
    movz x9, #((FB_BASE) >> 16), lsl #16
    movk x9, #((FB_BASE) & 0xffff)
1:  stp  x10, x10, [x9], #16
    cmp  x9, x11
    b.lo 1b

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
