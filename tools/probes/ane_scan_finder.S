/* Scan-finder probe: which buffer is the panel actually scanning?
 *
 * The RCH probe covers only DATA_ADDR0 of the four DSS read channels. The
 * vendor headers define three buffer slots per channel (+0x60, +0x84, +0xA8,
 * soc_dss_interface.h), and if the loader or the scanner uses slot 1 or 2,
 * the RCH fills never show - an empty readout indistinguishable from "the
 * probe did not run". This probe removes that ambiguity by testing every
 * candidate and encoding the answer in the *position* of a green band rather
 * than in a colour:
 *
 *   for each candidate k (1..13):
 *     - black the whole FILL_LEN,
 *     - paint a white band at position 0 (liveness),
 *     - paint one green band at position k.
 *
 * Whichever buffer the panel scans shows [white band, one green band]; the
 * green band's index names the candidate. Position survives colour shifts and
 * camera colour error, and 13 candidates fit without exceeding the readable
 * hue budget (a hue legend would not).
 *
 * Legend (green band index -> candidate):
 *    1 VG0 ADDR0   2 VG0 ADDR1   3 VG0 ADDR2
 *    4 VG1 ADDR0   5 VG1 ADDR1   6 VG1 ADDR2
 *    7  G0 ADDR0   8  G0 ADDR1   9  G0 ADDR2
 *   10  G1 ADDR0  11  G1 ADDR1  12  G1 ADDR2
 *   13 fallback 0x31000000 (the kernel-reserved graphic region; the fb2 probe
 *      already showed this one is NOT scanned in the handoff state, so it
 *      doubles as a control: if 13 appears, something else is wrong).
 *
 * Each candidate is only touched when the register reads back a plausible
 * DRAM address (>= 1 MiB, < 0xC0000000; the DMA source must be DRAM - the
 * DSS itself lives at 0xE86..., which is why the upper bound sits below it).
 * Unset slots read 0 and are skipped.
 *
 * Ends in a hang: the loader's watchdog then falls back to fastboot on its
 * own (~4.5 min; docs/ANE_BOOT_CONTRACT.md section 12).
 */

.section .text, "ax"
.balign 4
.global _start

/* paint: black fill, white band 0, green band \k, at w20 - only when w20 is
   plausible DRAM. clobbers w14/w21/w22/w24/w25/x9/x10 */
.macro paint_k k
    cmp  w20, #0x00100000
    b.lo 9f
    movz w13, #0xC000, lsl #16
    cmp  w20, w13
    b.hs 9f
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
    /* band 0: white liveness */
    movz w21, #0xFFFF
    movk w21, #0xFFFF, lsl #16          /* white 0xFFFFFFFF */
    mov  w24, w20
    mov  w14, w24
    movz w25, #((BAND) >> 16), lsl #16
    movk w25, #((BAND) & 0xffff)
    add  w25, w24, w25
    orr  x10, x21, x21, lsl #32
2:  stp  x10, x10, [x14], #16
    cmp  w14, w25
    b.lo 2b
    /* band \k: green */
    mov  w22, #\k
    add  w24, w20, w22, lsl #16         /* BAND is 0x10000: k*BAND = k<<16 */
    mov  w14, w24
    movz w21, #0xFF00
    movk w21, #0xFF00, lsl #16          /* green 0xFF00FF00 */
    movz w25, #((BAND) >> 16), lsl #16
    movk w25, #((BAND) & 0xffff)
    add  w25, w24, w25
    orr  x10, x21, x21, lsl #32
3:  stp  x10, x10, [x14], #16
    cmp  w14, w25
    b.lo 3b
9:
.endm

_start:
    /* MMU off first: the loader hands over with it on and its tables do not
       cover the regions we touch (measured - the first access faults). */
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

    /* 1..3: VG0 ADDR0/1/2 */
    movz w19, #((RCH_VG0_BASE) >> 16), lsl #16
    movk w19, #((RCH_VG0_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    paint_k 1
    ldr  w20, [x19, #0x84]
    paint_k 2
    ldr  w20, [x19, #0xA8]
    paint_k 3

    /* 4..6: VG1 ADDR0/1/2 */
    movz w19, #((RCH_VG1_BASE) >> 16), lsl #16
    movk w19, #((RCH_VG1_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    paint_k 4
    ldr  w20, [x19, #0x84]
    paint_k 5
    ldr  w20, [x19, #0xA8]
    paint_k 6

    /* 7..9: G0 ADDR0/1/2 */
    movz w19, #((RCH_G0_BASE) >> 16), lsl #16
    movk w19, #((RCH_G0_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    paint_k 7
    ldr  w20, [x19, #0x84]
    paint_k 8
    ldr  w20, [x19, #0xA8]
    paint_k 9

    /* 10..12: G1 ADDR0/1/2 */
    movz w19, #((RCH_G1_BASE) >> 16), lsl #16
    movk w19, #((RCH_G1_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    paint_k 10
    ldr  w20, [x19, #0x84]
    paint_k 11
    ldr  w20, [x19, #0xA8]
    paint_k 12

    /* 13: the fixed graphic-region fallback */
    movz w20, #((FALLBACK_BASE) >> 16), lsl #16
    movk w20, #((FALLBACK_BASE) & 0xffff)
    paint_k 13

.Lhang:
    wfe
    b    .Lhang
