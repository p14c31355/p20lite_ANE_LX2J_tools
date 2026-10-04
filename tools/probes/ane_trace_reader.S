/* The trace reader: salvage the l1d trace out of the black box and make it
 * visible.
 *
 * Why this exists: the l1d / l2 / reason2 probes end in a loader park, so the
 * only channel out of that boot is reserved RAM.  The Fullerene builds carry
 * the l1d trace into the black box's record ring at boot (main.rs, right after
 * mark_entry) - durable, but unreadable: adb's shell is denied /sys/fs/pstore
 * and /data, and the ring is not pstore-formatted.  This probe is the reader:
 * it scans the ring for CODE_L1D_TRACE (96) records, rebuilds the 24
 * [step, value] entries into a scratch table, and re-emits the diagnostic
 * steps into the step-mark block, which the paint probe already renders as
 * colour bands.  Webcam in, data out - no root, no adb, no host channel.
 *
 * Geometry (blackbox.rs): ring base = region base + 0x100 + 32; record = 32
 * bytes [seq u32, code u32, stamp u64, arg0 u64, arg1 u64]; the capture packs
 * two entries per record as (step << 32 | value) in arg0/arg1, with the
 * record's stamp = the pair index i (0..11).  The 24-entry table slot for a
 * step s is TRACE_BASE + 8*(s-1), matching the l1d probe's own layout.
 *
 * The emitted 12 steps (in this order) and what their top byte decides:
 *   1  CRG+0x40 clocks   2  PCTRL+0x64 abb   3  CRG+0x94 rstdis
 *   4  AHBIF ctrl0       5  AHBIF ctrl3 eye  10 DCTL attach
 *   12 GUSBCFG pre      14  GUSBCFG post     15 PPLL0 pre
 *   16 PPLL0 post       21  GUSBCFG readback 23 DCTL readback
 * A byte of 0xEE means "that step is not in the ring" (a partial trace).
 *
 * WITH_SEED=1 (QEMU): plant three synthetic records first so the scan, the
 * extraction and the emit are proven mechanically before any device run.
 */
.section .text, "ax"
.balign 4
.global _start

.if WITH_SEED
/* seed one ring record at [x20] and advance: x0=seq, x1=stamp, x2=arg0, x3=arg1 */
.macro seed_rec
    str  w0, [x20], #4
    mov  w14, #96
    str  w14, [x20], #4
    str  x1, [x20], #8
    str  x2, [x20], #8
    str  x3, [x20], #8
.endm
.endif

_start:
    /* MMU off: the loader hands over with it on (the rule for every probe). */
    mrs  x0, CurrentEL
    cmp  x0, #0x4
    b.eq 8f
    cmp  x0, #0x8
    b.eq 9f
    b    7f
8:  mrs  x1, sctlr_el1
    tbnz x1, #0, 10f
    b    7f
9:  mrs  x1, sctlr_el2
    tbnz x1, #0, 11f
    b    7f
10: bic  x1, x1, #1
    msr  sctlr_el1, x1
    isb
    b    7f
11: bic  x1, x1, #1
    msr  sctlr_el2, x1
    isb
7:

    /* TRACE_BASE: the 24-entry scratch table (the l1d's slot; its raw words
       now live only in the ring, so reusing this RAM corrupts nothing) */
    movz x19, #((TRACE_BASE) >> 16), lsl #16
    movk x19, #((TRACE_BASE) & 0xffff)

.if WITH_SEED
    /* three synthetic records: steps 1,2 (0x46, 0x05000000) in pair 0;
       steps 15,16 (both 0x04000001) in pair 7; steps 23,24 (0,0) in pair 11 */
    movz x20, #((BOX_BASE) >> 16), lsl #16
    movk x20, #((BOX_BASE) & 0xffff)
    add  x20, x20, #0x120
    mov  x1, #0               /* pair 0 */
    movz x2, #0x1, lsl #32
    movz x9, #0x46
    orr  x2, x2, x9
    movz x3, #0x2, lsl #32
    movz x9, #0x0500, lsl #16
    orr  x3, x3, x9
    mov  x0, #1
    seed_rec
    mov  x1, #7               /* pair 7 */
    movz x2, #0x0F, lsl #32
    movz x9, #0x0001
    movk x9, #0x0400, lsl #16
    orr  x2, x2, x9
    movz x3, #0x10, lsl #32
    orr  x3, x3, x9
    mov  x0, #2
    seed_rec
    mov  x1, #11              /* pair 11 */
    movz x2, #0x17, lsl #32
    movz x3, #0x18, lsl #32
    mov  x0, #3
    seed_rec
.endif

    /* zero the 24-entry table (48 u32) */
    movz x20, #((BOX_BASE) >> 16), lsl #16
    movk x20, #((BOX_BASE) & 0xffff)
    add  x20, x20, #0x120
    mov  w14, #48
    mov  x15, x19
1:  str  wzr, [x15], #4
    subs w14, w14, #1
    b.ne 1b

    /* scan the ring's 256 records for the capture's (code 96).
       Counter in w29: the body uses x14 as a table address. */
    mov  w29, #256
2:  ldr  w10, [x20, #4]
    cmp  w10, #96
    b.ne 3f
    ldr  x13, [x20, #8]        /* stamp = pair index i */
    ldr  x11, [x20, #16]       /* arg0 = (s0 << 32 | v0) */
    ldr  x12, [x20, #24]       /* arg1 = (s1 << 32 | v1) */
    add  x14, x19, x13, lsl #4 /* table byte offset = 16 * i */
    lsr  x15, x11, #32
    str  w15, [x14]            /* s0 */
    str  w11, [x14, #4]        /* v0 */
    lsr  x15, x12, #32
    str  w15, [x14, #8]        /* s1 */
    str  w12, [x14, #12]       /* v1 */
3:  add  x20, x20, #32
    subs w29, w29, #1
    b.ne 2b

    /* emit: header, then one top byte per diagnostic step */
    movz x21, #((MARKS_BASE) >> 16), lsl #16
    movk x21, #((MARKS_BASE) & 0xffff)
    mov  w10, #0x4E41
    movk w10, #0x4D45, lsl 16   /* "ANEM" little-endian (0x4D454E41) */
    str  w10, [x21]
    mov  w10, #12
    str  w10, [x21, #4]
    add  x22, x21, #8           /* byte cursor */

    adr  x23, .Lsteps           /* the 12 wanted step numbers */
    mov  w24, #12               /* loop counter */
4:  ldrb w25, [x23], #1         /* the wanted step */
    mov  w26, #0xEE             /* the not-found byte */
    mov  x27, x19               /* walk the table's 24 entries */
    mov  w28, #24
5:  ldr  w10, [x27]             /* step field */
    cmp  w10, w25
    b.eq 6f
    add  x27, x27, #8
    subs w28, w28, #1
    b.ne 5b
    b    9f                    /* not found: keep 0xEE */
6:  ldr  w26, [x27, #4]         /* the value */
    lsr  w26, w26, #24          /* its top byte */
9:  strb w26, [x22], #1
    subs w24, w24, #1
    b.ne 4b

.Lhalt:
    wfe
    b    .Lhalt

.balign 4
.Lsteps:
    .byte 1, 2, 3, 4, 5, 10, 12, 14, 15, 16, 21, 23
