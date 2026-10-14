/* The reason probe: can the payload put the loader into fastboot on its own?
 *
 * Why this should work (all from primary sources; nothing assumed):
 *
 *   - The device tree declares the PMIC as MMIO: `/pmic@FFF34000` is
 *     `hisilicon,hisi-pmic`, and `/clocks@0/clk_pmuctrl@0xfff34000`
 *     (`hisilicon,hi6421pmic`) is accessed by the clock driver with a plain
 *     `of_iomap` (drivers/clk/hisi/clk-kirin-common.c, HS_PMUCTRL case). So
 *     the PMIC's register space is a memory window at 0xFFF34000, not a
 *     serial bus.
 *   - `hisi_pmic_reg_read/write(reg)` therefore resolves to a load/store in
 *     that window, and the reboot reason is one byte of PMIC register 0x18B:
 *     `PMIC_HRST_REG0_ADDR(0)` = base + 0x18B with `RST_FLAG_MASK = 0xFF`
 *     (drivers/hisi/ap/platform/hi6250/mntn_public_interface.h), written by
 *     `set_reboot_reason()` in the kernel's blackbox adapter.
 *   - The value that means "bootloader" is BOOTLOADER = 0x01 (same header,
 *     the reboot-reason enum).
 *   - The loader reads that reason at every boot (`reboot_reason_ops`), which
 *     is the mechanism `adb reboot bootloader` uses.
 *
 * So: write 0x01 to the byte at 0xFFF34000 + 0x18B, then reset. If the loader
 * comes up in fastboot, button-free cycles exist and this file is the whole
 * mechanism.
 *
 * Failure mode is safe: if the write does not take, the reset is an ordinary
 * reboot and the probe runs again - a visible loop, same as the other probes.
 */
.section .text, "ax"
.balign 4
.global _start

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

    /* the reason write: byte 0x01 at PMIC_BASE + 0x18B */
    movz x9, #((PMIC_BASE) >> 16), lsl #16
    movk x9, #((PMIC_BASE) & 0xffff)
    mov  w10, #0x01
    strb w10, [x9, #0x18B]

.if WITH_TRACE
    /* record [step, the byte read back] so QEMU proves both the write and the
       window's read-write behaviour */
    movz w15, #((TRACE_BASE) >> 16), lsl #16
    movk w15, #((TRACE_BASE) & 0xffff)
    mov  w16, #1
    str  w16, [x15]
    ldrb w17, [x9, #0x18B]
    str  w17, [x15, #4]
.endif

    /* PSCI SYSTEM_RESET: with the reason written, the loader should now enter
       fastboot instead of looping back into this kernel. */
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
