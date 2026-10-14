/* The key probe: find which PMIC register carries the volume/power key state.
 *
 * Why: the loader decides "boot to fastboot" from the KEY STATE at boot (the
 * physical Vol-Down+Power combo), not from the reboot-reason register - the
 * reason-probe v1 negative result and adb's BCB-based reboot both say so.
 * If the key state lives in a writable PMIC register, a probe can hold it
 * "pressed" across a reset and get fastboot with no hands.
 *
 * Method: read-only sweep of the key candidates, traced.  Run it once, have
 * the user hold Vol-Down, run it again, diff the traces: the register whose
 * value changes is the key's.  No guessing, no writes.
 *
 * Sources for the candidates:
 *   - drivers/misc/hi6421v600-irq.c / mfd hi6421 family (upstream): the PMIC
 *     IRQ status register 0x212 carries POWERKEY_DOWN (bit 7) and POWERKEY_UP
 *     (bit 6); the mask register is 0x202 with the same bit map.
 *   - The ANE's PMIC is the MMIO hi6421 at 0xFFF34000 (the same window the
 *     0x18B reason byte and the 0x10F abb byte live in).
 *   - The HRST/reason window 0x180..0x190 and the ABB word 0x108 are swept
 *     too, as positive controls for the window staying readable.
 *
 * Trace (device build, at the l1d's slot; the format is the shared
 * [step, value] layout so the stepmarks2 carry-over and the trace reader
 * both see it unchanged):
 *   1..12  the 12 candidate words, in the .Lregs order below.
 *
 * End: PSCI SYSTEM_RESET (an ordinary reboot; this probe writes nothing).
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

    /* the sweep: one word per candidate, traced in order */
    adr  x20, .Lregs
    mov  w21, #12               /* the candidate count */
    mov  w22, #1                /* the trace step */
1:  ldr  w23, [x20], #4         /* the candidate offset */
    ldr  w10, [x9, x23]         /* the value */
    mov  w16, w22
.if WITH_TRACE
    movz w15, #((TRACE_BASE) >> 16), lsl #16
    movk w15, #((TRACE_BASE) & 0xffff)
    mov  w24, w22
    lsl  w24, w24, #3           /* the slot = 8*(step-1) */
    sub  w24, w24, #8
    add  x15, x15, x24
    str  w16, [x15]
    str  w10, [x15, #4]
.endif
    add  w22, w22, #1
    subs w21, w21, #1
    b.ne 1b

    /* PSCI SYSTEM_RESET: an ordinary reboot; the trace is the deliverable */
    movz w0, #0x0009
    movk w0, #0x8400, lsl 16
    mov  x1, xzr
    mov  x2, xzr
    mov  x3, xzr
    smc  #0

.Lhalt:
    wfe
    b    .Lhalt

.balign 4
.Lregs:
    .word 0x0108                /* the abb word (the known-live control) */
    .word 0x0180                /* the HRST window, as the reason probe */
    .word 0x0184
    .word 0x0188
    .word 0x018C
    .word 0x0190
    .word 0x0200                /* the hi6421 IRQ area (mask 0x202/0x212) */
    .word 0x0202
    .word 0x0208
    .word 0x0210
    .word 0x0212
    .word 0x0213
