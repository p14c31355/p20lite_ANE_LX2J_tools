/* The pmsg dumper: carry the probe trace out through Android's own pstore.
 *
 * Why: this kernel has no /dev/mem and no /proc/kcore (checked against
 * /proc/config.gz), so once Android is up there is no way to read reserved RAM
 * directly.  What IS readable is /sys/fs/pstore/pmsg-ramoops-0 - Android's
 * ramoops driver presents the pmsg zone as a file, and root can read it.  The
 * zone has been measured to keep writes (blackbox.rs: "a text written into
 * the pmsg zone's data area ... was still readable two boots later").
 *
 * Layout (from blackbox.rs, which writes the same zone): header is
 * {sig u32, start u32, size u32} at the zone base (fs/pstore/ram_core.c:32-37),
 * sig = 0 ^ PERSISTENT_RAM_SIG = 0x43474244, data follows at +12, and the
 * validity conditions are size <= zone_size && start <= size
 * (ram_core.c:556-566).  start stays 0.
 *
 * What this appends, in one 128-byte record at base + 12 + size:
 *   +0    8 bytes  "ANEPv1->"   (a fixed marker: proves the mechanism)
 *   +8   96 bytes  the raw 24-entry [step, value] trace at TRACE_BASE
 *   +104 24 bytes  the step-mark block (magic, count, marks)
 * and then commits the new size (payload first, size second - a torn write
 * leaves the previous consistent state, the commit pattern blackbox.rs uses).
 *
 * WITH_SEED (QEMU): plant a header + a few bytes, so the append, the cap and
 * the size update are proven mechanically before any device run.
 */
.section .text, "ax"
.balign 4
.global _start

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

    /* the pmsg zone */
    movz x9, #((PMSG_BASE) >> 16), lsl #16
    movk x9, #((PMSG_BASE) & 0xffff)

.if WITH_SEED
    /* QEMU: header {sig, 0, 5} + "hello", so the append point is known */
    movz w10, #0x4244
    movk w10, #0x4347, lsl 16
    str  w10, [x9]
    str  wzr, [x9, #4]
    mov  w10, #5
    str  w10, [x9, #8]
    movz w10, #0x6568               /* "he" */
    movk w10, #0x6c6c, lsl 16       /* "ll" */
    str  w10, [x9, #12]
    movz w10, #0x0001               /* 'o' then 0x01: 5 bytes of log */
    movk w10, #0x0100, lsl 16
    strb w10, [x9, #16]
    lsr  w10, w10, #8
    strb w10, [x9, #17]
    /* seed the trace: 24 words 0x100..0x117 (so the appended copy is exact) */
    movz x14, #((TRACE_BASE) >> 16), lsl #16
    movk x14, #((TRACE_BASE) & 0xffff)
    mov  w15, #0x0100
    mov  w16, #24
2:  str  w15, [x14], #4
    add  w15, w15, #1
    subs w16, w16, #1
    b.ne 2b
    /* and the marks block: "ANEM", count 2, "ab" */
    movz x14, #((MARKS_BASE) >> 16), lsl #16
    movk x14, #((MARKS_BASE) & 0xffff)
    movz w10, #0x4E41
    movk w10, #0x4D45, lsl 16
    str  w10, [x14]
    mov  w10, #2
    str  w10, [x14, #4]
    movz w10, #0x6261               /* "ab" */
    strh w10, [x14, #8]
.endif

    ldr  w10, [x9, #8]              /* current size */
    movz w13, #((PMSG_MAX) >> 16), lsl #16
    movk w13, #((PMSG_MAX) & 0xffff)
    cmp  w10, w13
    b.hs .Lfull                     /* no room: leave the zone alone */

    /* cursor = base + 12 + size */
    add  x11, x9, #12
    add  x11, x11, w10, uxtw

    /* marker: "ANEPv1->" */
    ldr  x12, .Lmark1
    str  x12, [x11], #8

    /* the raw trace: 24 u32 words = 96 bytes */
    movz x14, #((TRACE_BASE) >> 16), lsl #16
    movk x14, #((TRACE_BASE) & 0xffff)
    mov  w15, #6                    /* 6 x 16 bytes */
1:  ldp  x16, x17, [x14], #16
    stp  x16, x17, [x11], #16
    subs w15, w15, #1
    b.ne 1b

    /* the step-mark block: 24 bytes */
    movz x14, #((MARKS_BASE) >> 16), lsl #16
    movk x14, #((MARKS_BASE) & 0xffff)
    ldp  x16, x17, [x14]
    stp  x16, x17, [x11], #16
    ldr  x16, [x14, #16]
    str  x16, [x11]

    /* commit: the payload is in place; now the size, then the signature
       (payload first, size second: a torn write leaves the previous
       consistent state - the same commit order blackbox.rs uses) */
    add  w10, w10, #128
    str  w10, [x9, #8]
    movz w12, #0x4244
    movk w12, #0x4347, lsl 16
    str  w12, [x9]

.Lfull:
    /* PSCI SYSTEM_RESET: the next boot is the readout */
    movz w0, #0x0009
    movk w0, #0x8400, lsl 16
    mov  x1, xzr
    mov  x2, xzr
    mov  x3, xzr
    smc  #0

.Lhalt:
    wfe
    b    .Lhalt

.balign 8
.Lmark1:
    .ascii "ANEPv1->"
