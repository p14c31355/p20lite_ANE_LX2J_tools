/* The reason probe v2: read the PMIC's reboot-reason window before writing it.
 *
 * v1 (ane_reason_probe.S) wrote 0x01 to the reason byte and reset, and the
 * device did NOT come up in fastboot.  But v1's device build carried no trace,
 * so the run left no record of whether the write landed, what the window
 * contained, or whether the byte even reads back - the exact blind spot the
 * l1d work fixed for the USB probes.  This version reads first, traces
 * everything, then writes and traces the readback.
 *
 * Sources (unchanged from v1, all primary):
 *   - `/pmic@FFF34000` is `hisilicon,hisi-pmic`, a memory window (the clock
 *     driver of_iomaps the sibling clk_pmuctrl@0xfff34000).
 *   - The reboot reason is PMIC register 0x18B, RST_FLAG_MASK 0xFF
 *     (drivers/hisi/ap/platform/hi6250/mntn_public_interface.h).
 *   - BOOTLOADER = 0x01 in the reboot-reason enum (same header).
 *   - The ABB control word at +0x108 is the positive control: the l1 probe
 *     writes 0x10F's byte successfully (the abb gate), so a window where that
 *     word reads back anything sane proves the window is alive.
 *
 * Trace (device build: on, at the l1d's slot in the pstore window, same
 * [step, value] layout, so the stepmarks2 carry-over reads it unchanged):
 *   1..6  words 0x108, 0x180, 0x184, 0x188, 0x18C, 0x190
 *   7     byte 0x18B (pre-write)
 *   8     the write 0x01 -> 0x18B, then the byte read back
 *   9     word 0x188 again (the written byte in place)
 *
 * End: PSCI SYSTEM_RESET.  If the loader reads the reason as it does for
 * `adb reboot bootloader`, it comes up in fastboot; if not, this is an
 * ordinary reboot and the trace still tells the story.
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
    /* MMU off: the loader hands over with it on, and its tables do not cover
       the PMIC window (measured; the rule for every probe here). */
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

    /* 1: positive control - the window's own known-live register */
    ldr  w10, [x9, #0x108]
    trace 1
    /* 2..6: the HRST window words around the reason byte */
    ldr  w10, [x9, #0x180]
    trace 2
    ldr  w10, [x9, #0x184]
    trace 3
    ldr  w10, [x9, #0x188]
    trace 4
    ldr  w10, [x9, #0x18C]
    trace 5
    ldr  w10, [x9, #0x190]
    trace 6
    /* 7: the reason byte as the loader last left it */
    ldrb w10, [x9, #0x18B]
    trace 7

    /* 8: write BOOTLOADER and read it back immediately */
    mov  w10, #0x01
    strb w10, [x9, #0x18B]
    ldrb w10, [x9, #0x18B]
    trace 8

    /* 9: the word containing it (little-endian: byte 3) */
    ldr  w10, [x9, #0x188]
    trace 9

    /* PSCI SYSTEM_RESET */
    movz w0, #0x0009
    movk w0, #0x8400, lsl 16
    mov  x1, xzr
    mov  x2, xzr
    mov  x3, xzr
    smc  #0

    /* reached only if the reset did not happen */
.Lhalt:
    wfe
    b    .Lhalt
