/* The key writer: press a PMIC register field in software, then reset.
 *
 * This is Stage 2 of the combo automation.  Once the key probe's traces name
 * the register that carries the button state, build this probe with:
 *     --defsym KEYREG=<the register offset>
 *     --defsym KEYVAL=<the value that means "held">
 * and the sequence is: read the register (trace: before), write KEYVAL
 * (trace: the readback), read it again (trace: after), then PSCI reset.  If
 * the loader boots fastboot from that, the physical combo is automated.
 *
 * Safety shape: single register, read before and after, everything traced
 * (the l1d discipline - a failure must leave its reason behind).  Defaults
 * ARE the reason-probe v2's already-tested write (0x18B <- 0x01), so a build
 * with no defsyms is a rehearsal of known behaviour, not a new risk.
 *
 * Trace (device build, the shared [step, value] layout at the l1d slot):
 *   1  KEYREG before      2  readback after the write      3  KEYREG after
 *
 * End: PSCI SYSTEM_RESET, then the LOADER decides - and the catcher is
 * already waiting for the fastboot window if it does.
 */
.section .text, "ax"
.balign 4
.global _start

/* record [step, w10] into the trace array; empty when WITH_TRACE=0 */
.macro trace step
.if WITH_TRACE
    movz w15, #((TRACE_BASE) >> 16), lsl #16
    movk w15, #((TRACE_BASE) & 0xffff)
    mov  w16, #\step
    str  w16, [x15, #(8 * (\step - 1))]
    str  w10, [x15, #(8 * (\step - 1) + 4)]
.endif
.endm

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

    movz x9, #((PMIC_BASE) >> 16), lsl #16
    movk x9, #((PMIC_BASE) & 0xffff)
    add  x12, x9, #KEYREG       /* the target register's address */

    /* 1: the register as the loader last left it */
    ldr  w10, [x12]
    trace 1

    /* 2: write the held value (byte width - the key registers are byte
       fields) and read it back */
    movz w14, #((KEYVAL) & 0xff)
    strb w14, [x12]
    ldr  w10, [x12]
    trace 2

    /* 3: a second read (the value after the store settling) */
    ldr  w10, [x12]
    trace 3

    /* PSCI SYSTEM_RESET */
    movz w0, #0x0009
    movk w0, #0x8400, lsl 16
    mov  x1, xzr
    mov  x2, xzr
    mov  x3, xzr
    smc  #0

.Lhalt:
    wfe
    b    .Lhalt
