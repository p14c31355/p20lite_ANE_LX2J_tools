/* Paint probe: put Fullerene's step-mark scratch on the screen.
 *
 * The ANE-LX2J has no console an outside observer can read. A marked
 * Fullerene boot writes step marks into a scratch word inside the reserved
 * ramoops window; this probe - flashed as the NEXT boot - reads those marks
 * and paints them as large colour bands at every candidate scan-out buffer,
 * so the webcam (ane_cam_read.py) can read how far the marked boot got.
 *
 * Marks scratch layout, written by the kernel's `ane_step_byte`:
 *   +0  u32 magic "ANEM" (0x4D454E41)
 *   +4  u32 count (bytes follow at +8, count <= 12)
 * The address is the unused tail of the ramoops console zone: Linux's own
 * writers only touch the first kilobyte of that zone, and nothing else in
 * these bare-metal boots runs at all.
 *
 * Candidate scan-out buffers: the DSS read channels' DMA source registers -
 * four channels, three buffer slots each (+0x60, +0x84, +0xA8, all defined by
 * the vendor headers) - plus the fixed graphic-region fallback. The pattern
 * is painted at EVERY candidate, so whichever buffer the panel actually scans
 * shows the bands and the others stay invisible. (The scan-finder probe uses
 * the same candidate list to name the scanned buffer by band position.)
 *
 * Bands: band k starts at buffer offset k*BAND and is BAND bytes of one
 * colour. Band 0 is the liveness band (white): it appears whenever this
 * probe ran. Bands 1..count carry the marks, so the number of visible bands
 * minus one = the number of step marks written = how far the marked boot got.
 * Before painting, the whole FILL_LEN is blacked so the bands have contrast.
 *
 *   PAL = white, green, blue, yellow, cyan, magenta, red, orange  (k % 8)
 *
 * Bands 14 and 15 are a read-only PMIC-window diagnostic (the reason the
 * reason-probe write may not have taken): band 14 reflects the byte at
 * PMIC+0x18B and band 15 the low byte at PMIC+0x62C - green when the read is
 * a small, reason-like value (<= 8), red otherwise. They are painted in a
 * SECOND pass, after the marks bands, so a faulting read (unmapped window)
 * leaves the marks visible and simply drops these two bands.
 *
 * Ends in a hang (no reset): the loader's watchdog then falls back to
 * fastboot on its own (~4.5 min; docs/ANE_BOOT_CONTRACT.md section 12), so
 * the night runner can restore the stock kernel without any key press.
 */

.section .text, "ax"
.balign 4
.global _start

/* paint band \idx (=w22 via w23) colour into w21; clobbers w21 only */
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
   plausible RAM (>= 1 MiB, < 0xC0000000); clobbers w14/w22/w23/w24/w25/x9/x10 */
.macro try_paint
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
    mov  w22, #0
2:  and  w23, w22, #7
    setcolor w23
    add  w24, w20, w22, lsl #16         /* BAND is 0x10000: k*BAND = k<<16 */
    mov  w14, w24
    movz w25, #((BAND) >> 16), lsl #16
    movk w25, #((BAND) & 0xffff)        /* low half is zero; explicit so the
                                           movz/movk audit stays clean */
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

/* bands 14 (colour w30) and 15 (colour w28) at w20 - the PMIC diagnostic.
   Same plausibility gate; clobbers w13/w14/w21/w22/w24/w25/x10 */
.macro paint_diag
    cmp  w20, #0x00100000
    b.lo 9f
    movz w13, #0xC000, lsl #16
    cmp  w20, w13
    b.hs 9f
    mov  w22, #14
    add  w24, w20, w22, lsl #16
    mov  w14, w24
    orr  x10, x30, x30, lsl #32
    movz w25, #((BAND) >> 16), lsl #16
    movk w25, #((BAND) & 0xffff)
    add  w25, w24, w25
4:  stp  x10, x10, [x14], #16
    cmp  w14, w25
    b.lo 4b
    mov  w22, #15
    add  w24, w20, w22, lsl #16
    mov  w14, w24
    mov  w21, w28
    orr  x10, x21, x21, lsl #32
    movz w25, #((BAND) >> 16), lsl #16
    movk w25, #((BAND) & 0xffff)
    add  w25, w24, w25
5:  stp  x10, x10, [x14], #16
    cmp  w14, w25
    b.lo 5b
9:
.endm

/* run \what for every candidate address: four channels x three slots each,
   plus the fixed fallback - the same list the scan-finder probes */
.macro each_candidate what
    movz w19, #((RCH_VG0_BASE) >> 16), lsl #16
    movk w19, #((RCH_VG0_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    \what
    ldr  w20, [x19, #0x84]
    \what
    ldr  w20, [x19, #0xA8]
    \what
    movz w19, #((RCH_VG1_BASE) >> 16), lsl #16
    movk w19, #((RCH_VG1_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    \what
    ldr  w20, [x19, #0x84]
    \what
    ldr  w20, [x19, #0xA8]
    \what
    movz w19, #((RCH_G0_BASE) >> 16), lsl #16
    movk w19, #((RCH_G0_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    \what
    ldr  w20, [x19, #0x84]
    \what
    ldr  w20, [x19, #0xA8]
    \what
    movz w19, #((RCH_G1_BASE) >> 16), lsl #16
    movk w19, #((RCH_G1_BASE) & 0xffff)
    ldr  w20, [x19, #0x60]
    \what
    ldr  w20, [x19, #0x84]
    \what
    ldr  w20, [x19, #0xA8]
    \what
    movz w20, #((FALLBACK_BASE) >> 16), lsl #16
    movk w20, #((FALLBACK_BASE) & 0xffff)
    \what
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
    cmp  w26, #12
    b.ls .Lhave
    mov  w26, #12
    b    .Lhave
.Lnostamp:
    mov  w26, #0

.Lhave:
    /* --- pass 1: the marks bands at every candidate --- */
    each_candidate try_paint

    /* --- PMIC window diagnostic (read-only; see the header) --- */
    movz x26, #((PMIC_BASE) >> 16), lsl #16
    movk x26, #((PMIC_BASE) & 0xffff)
    ldrb w28, [x26, #0x18B]
    ldr  w29, [x26, #0x62C]
    and  w29, w29, #0xFF
    movz w30, #0x00FF
    movk w30, #0xFF00, lsl #16          /* red = not reason-like */
    cmp  w28, #8
    b.hi 6f
    movz w30, #0xFF00
    movk w30, #0xFF00, lsl #16          /* green = small value */
6:  movz w28, #0x00FF                   /* w28's byte is consumed: reuse for the
                                           band-15 colour (w31 is not a register) */
    movk w28, #0xFF00, lsl #16
    cmp  w29, #8
    b.hi 7f
    movz w28, #0xFF00
    movk w28, #0xFF00, lsl #16
7:
    /* --- pass 2: bands 14/15 (a fault in the reads above leaves pass 1
           visible on screen; the missing bands are the diagnosis) --- */
    each_candidate paint_diag

    /* stay: the bands are the readout, so keep them on screen */
.Lhang:
    wfe
    b    .Lhang
