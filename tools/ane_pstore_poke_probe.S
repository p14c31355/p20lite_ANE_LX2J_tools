/* Combined probe: (1) does the pstore channel work with the MMU off, and
 * (2) is the PL011 write that ends Fullerene's boot fatal on the device?
 *
 * Order matters: the pstore record is written first, so if the UART writes
 * fault, the record still exists and the readback answers question 1 anyway.
 *
 * The record format is the one the ramoops driver validates (and the one the
 * blackbox module and the earlier mark probes use): sig "DBGC", start 0, text,
 * size last. The pmsg zone on this handset sits at 0x348e0000 (the ANE
 * layout), so the record goes to 0x348e0000 + 12.
 *
 * Readout: reboot the device to Android and read /sys/fs/pstore.
 *   pmsg-ramoops-0 contains "\nP3:U"  -> the pstore channel works
 *   machine loops (unlocked warning repeats) -> the UART writes are harmless
 *   rescue ~30 s                              -> the UART write is fatal, and
 *                                               Fullerene's console must enable
 *                                               its clock before writing
 */

.section .text, "ax"
.balign 4
.global _start

_start:
    /* MMU off first (measured: the loader leaves it on, and its tables do not
     * cover the reserved regions - the first access would fault). */
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

    /* --- pstore record: "\nP3:U" (5 bytes) into the pmsg zone --- */
    movz x9, #0x348e, lsl #16       /* 0x348e0000 */
    mov  w10, #0x0A                 /* '\n' */
    strb w10, [x9, #12]
    mov  w10, #0x50                 /* 'P' */
    strb w10, [x9, #13]
    mov  w10, #0x33                 /* '3' */
    strb w10, [x9, #14]
    mov  w10, #0x3A                 /* ':' */
    strb w10, [x9, #15]
    mov  w10, #0x55                 /* 'U' */
    strb w10, [x9, #16]
    movz w10, #0x4244
    movk w10, #0x4347, lsl #16      /* "DBGC" */
    str  w10, [x9]
    str  wzr, [x9, #4]              /* start = 0 */
    mov  w10, #5
    str  w10, [x9, #8]              /* size last: the record becomes valid */

    /* --- PL011 poke at 0xfdf02000: the writes Fullerene's console makes --- */
    movz w9, #0x2000
    movk w9, #0xfdf0, lsl #16
    str  wzr, [x9, #0x30]           /* CR = 0 (the write Fullerene dies on) */
    movz w10, #0x0301               /* UARTEN | TXE | RXE */
    str  w10, [x9, #0x30]
    movz w10, #0x41                 /* 'A' to DR */
    str  w10, [x9]

    /* short hold, then the reset loop so a live machine is unmistakable */
    movz w11, #0x4000
    movk w11, #0x30, lsl #16
6:  subs w11, w11, #1
    b.ne 6b

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
