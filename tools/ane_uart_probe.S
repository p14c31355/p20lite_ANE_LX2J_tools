/* UART poke probe: is the PL011 write that killed Fullerene fatal on the device?
 *
 * QEMU says the stock-embedded Fullerene runs its whole early path and reaches
 * the console's first PL011 store (`str wzr, [0xfdf02030]`, image offset
 * 0xd1724, i.e. 0x41731724 in the patched layout). On the device that same
 * store is the first *device-specific* step, and it is where Fullerene dies.
 * If the UART's clock is gated at handoff, the write becomes a bus error - a
 * data abort into the loader's handler and then rescue.
 *
 * This probe asks exactly that question with the proven tiny form: clear the
 * MMU (as always), perform the same three PL011 accesses Fullerene would
 * (CR = 0 first, CR = UARTEN|TXE|RXE, then a byte to DR), then loop through
 * PSCI reset. Loop == the UART writes are harmless; rescue == they fault, and
 * Fullerene's console needs its clock enabled before the first write.
 */

.section .text, "ax"
.balign 4
.global _start

_start:
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

    /* PL011 at 0xfdf02000: DR +0x00, CR +0x30 */
    movz w9, #0x2000
    movk w9, #0xfdf0, lsl #16
    str  wzr, [x9, #0x30]           /* exactly the write Fullerene dies on */
    movz w10, #0x0301               /* UARTEN | TXE | RXE */
    str  w10, [x9, #0x30]
    movz w10, #0x41                 /* 'A' */
    str  w10, [x9]

    /* a short hold (in case something traces the bus), then the reset loop */
    movz w11, #0x2000
    movk w11, #0x10, lsl #16
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
