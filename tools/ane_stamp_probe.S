/* Stamp probe: identify which display channel points at the live scan
 * buffer, in ONE run, with no large fills.
 *
 * For each candidate (10 DMA channels, slot +0x60), if the value looks like
 * a usable address, paint a 2 MiB "stamp" at the value itself:
 *   runs 0..3 = the candidate's index in binary (white = 1, black = 0)
 *   runs 4..7 = white green blue yellow (the live-stamp marker)
 * each run = 256 KiB (STAMP_RUN=0x40000). A stamp in a buffer the panel
 * actually scans appears on screen, and its first four runs decode the
 * candidate index directly - no ambiguous overlaps, because 2 MiB stamps
 * only interleave when two candidates sit within 2 MiB of each other, and
 * even then each decoded bit block stands alone.
 *
 * Safety: the probe first copies itself to 0x50000000 (far above every
 * region that could plausibly hold a display buffer) and continues there,
 * so a fill can never sweep through the running code - the failure mode
 * that killed the old 12 MiB-fill paint probe. Address gate stays
 * [0x100000, 0xC0000000) plus the ramoops window skip.
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

/* paint the 8-run stamp at w20 (the candidate's value) with index w28.
 * gate: w20 in [0x100000, 0xC0000000), stamp range clear of ramoops.
 * clobbers w13/w14/w15/w17/w18/w21/w22/w23/w24/w25/x10 (never w20/w28) */
.macro stamp
    movz w13, #0x0010, lsl #16
    cmp  w20, w13
    b.lo 9f
    movz w13, #0xC000, lsl #16
    cmp  w20, w13
    b.hs 9f
    movz x15, #((STAMP_LEN) >> 16), lsl #16
    movk x15, #((STAMP_LEN) & 0xffff)
    add  w15, w15, w20
    movz w17, #((RAMO_WIN_START) >> 16), lsl #16
    movk w17, #((RAMO_WIN_START) & 0xffff)
    movz w18, #((RAMO_WIN_END) >> 16), lsl #16
    movk w18, #((RAMO_WIN_END) & 0xffff)
    cmp  w15, w17
    b.ls 60f
    cmp  w20, w18
    b.hs 60f
    b    9f
60:
    /* also refuse a stamp that would sweep the relocated code+scratch:
     * overlap with [RELOC_DEST, RELOC_DEST+0x2000) */
    movz w17, #((RELOC_DEST) >> 16), lsl #16
    movk w17, #((RELOC_DEST) & 0xffff)
    add  w18, w17, #0x2000
    cmp  w15, w17
    b.ls 6f
    cmp  w20, w18
    b.hs 6f
    b    9f
6:  mov  w22, #0
7:  cmp  w22, #4
    b.hs 8f
    lsr  w23, w28, w22
    tbz  w23, #0, 3f
    movz w21, #0xFFFF
    movk w21, #0xFFFF, lsl #16          /* bit set: white */
    b    4f
3:  movz w21, #0x0000
    movk w21, #0xFF00, lsl #16          /* bit clear: black */
4:  b    5f
8:  sub  w23, w22, #4
    setcolor w23                        /* runs 4..7: white green blue yellow */
5:  add  w24, w20, w22, lsl #18         /* STAMP_RUN is 0x40000: j*RUN = j<<18 */
    mov  w14, w24
    movz w25, #((STAMP_RUN) >> 16), lsl #16
    movk w25, #((STAMP_RUN) & 0xffff)
    add  w25, w24, w25
    orr  x10, x21, x21, lsl #32
2:  stp  x10, x10, [x14], #16
    cmp  w14, w25
    b.lo 2b
    add  w22, w22, #1
    cmp  w22, #8
    b.lo 7b
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
    /* QEMU: plant a candidate value into WCH1's slot to exercise the stamp */
    movz x19, #((RCH_WCH1_BASE) >> 16), lsl #16
    movk x19, #((RCH_WCH1_BASE) & 0xffff)
    movz w10, #0x4410, lsl #16          /* 0x44100000: qemu RAM, gated in */
    str  w10, [x19, #0x60]
.endif

    /* --- relocate: copy the payload to RELOC_DEST and continue there.
     * The destination must be readable+writable RAM on the target: the
     * proven zone is the graphic carveout band [0x31000000, 0x31800000)
     * which every probe's fallback fill has written without a fault.
     * (0x50000000 faulted the probe instantly on device - not RAM there.) */
    adr  x5, _start
    adr  x6, _end
    movz x7, #((RELOC_DEST) >> 16), lsl #16
    adr  x8, 6f
    sub  x8, x8, x5
    add  x8, x8, x7
    mov  x9, x5
7:  ldr  x10, [x9], #8
    str  x10, [x7], #8
    cmp  x9, x6
    b.lo 7b
    br   x8

6:
    /* --- the stamps at every plausible candidate --- */
    movz w19, #((RCH_VG0_BASE) >> 16), lsl #16
    movk w19, #((RCH_VG0_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    mov  w28, #0
    stamp

    movz w19, #((RCH_VG1_BASE) >> 16), lsl #16
    movk w19, #((RCH_VG1_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    mov  w28, #1
    stamp

    movz w19, #((RCH_G0_BASE) >> 16), lsl #16
    movk w19, #((RCH_G0_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    mov  w28, #2
    stamp

    movz w19, #((RCH_G1_BASE) >> 16), lsl #16
    movk w19, #((RCH_G1_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    mov  w28, #3
    stamp

    movz w19, #((RCH_D0_BASE) >> 16), lsl #16
    movk w19, #((RCH_D0_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    mov  w28, #4
    stamp

    movz w19, #((RCH_D1_BASE) >> 16), lsl #16
    movk w19, #((RCH_D1_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    mov  w28, #5
    stamp

    movz w19, #((RCH_D2_BASE) >> 16), lsl #16
    movk w19, #((RCH_D2_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    mov  w28, #6
    stamp

    movz w19, #((RCH_D3_BASE) >> 16), lsl #16
    movk w19, #((RCH_D3_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    mov  w28, #7
    stamp

    movz w19, #((RCH_WCH0_BASE) >> 16), lsl #16
    movk w19, #((RCH_WCH0_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    mov  w28, #8
    stamp

    movz w19, #((RCH_WCH1_BASE) >> 16), lsl #16
    movk w19, #((RCH_WCH1_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    mov  w28, #9
    stamp

    spin SPIN_HOLD, HOLD_REPEATS

    /* stay: the stamps are the readout, so keep them on screen */
.Lhang:
    wfe
    b    .Lhang

_end:
