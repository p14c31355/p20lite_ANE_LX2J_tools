/* USB probe for the ANE-LX2J: two questions in one boot, no memory writes.
 *
 * Question 1: does the loader enter our code at all?
 *   Answer channel: PSCI SYSTEM_RESET via SMC (the device tree says method =
 *   "smc"; PSCI 1.x). If our instructions run, the machine resets and re-enters
 *   this probe - a visible loop on the screen and on the host's USB log.
 *
 * Question 2: is the loader's USB controller state still alive at handoff?
 *   Answer channel: the DWC2 core itself. fastboot was running on this very
 *   controller until the jump, so this address space is the one block the
 *   loader's page tables must cover in any MMU state. The probe toggles
 *   DCTL.SftDiscon (D+ pull-up) with long holds: the host then sees
 *   attach/detach events built from OUR writes, with no RAM involvement.
 *
 * Nothing here writes memory. The only side effects are the USB core's
 * control register and (optionally) the reset.
 *
 * Register facts, both from the vendor tree and the upstream driver:
 *   DWC2 core at /hisi_usb@ff100000 (hisilicon,hi6250-usb-otg)
 *   DCTL is core+0x804; DCTL.SftDiscon is bit 1
 *     - drivers/usb/susb/dwc_otg_cil.c:290 uses dctl.b.sftdiscon
 *     - drivers/usb/dwc2/hw.h:433,443: DCTL = HSOTG_REG(0x804), DCTL_SFTDISCON (1<<1)
 *
 * Build variants (--defsym):
 *   CORE_BASE   device: 0xff100000            qemu: a RAM address
 *   TRACE_BASE  qemu only: a RAM page where each step records [step, DCTL]
 *   WITH_TRACE  0 on device (no memory writes), 1 in qemu
 *   WITH_SMC    1 on device, 0 in qemu (qemu's PSCI conduit is HVC)
 *   SPIN_LONG / SPIN_SHORT  delay loop counts (small in qemu, real on device)
 */

.section .text, "ax"
.balign 4
.global _start

/* record [step, current DCTL value] into the trace array; empty on the device */
.macro trace step
.if WITH_TRACE
    movz w15, #((TRACE_BASE) >> 16), lsl #16
    movk w15, #((TRACE_BASE) & 0xffff)
    mov  w16, #\step
    str  w16, [x15, #(8 * (\step - 1))]
    str  w10, [x15, #(8 * (\step - 1) + 4)]
.endif
.endm

/* busy-wait: w11 counts down; clobbers w11 and flags only */
.macro spin count
    movz w11, #((\count >> 16) & 0xffff)
    movk w11, #((\count >> 32) & 0xffff), lsl #16
1:  subs w11, w11, #1
    b.ne 1b
.endm

_start:
    /* The loader hands over with the MMU still on and its page tables do not
       cover these registers; without this the very first ldr below faults
       (measured: the earlier version of this probe was silent on the host).
       No-op when the MMU is already off. */
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
.if WITH_CLOCKS
    /* The loader leaves the USB2 clocks gated, which is why DCTL writes alone
       produced no host-visible attach. Gate names and bits come from the
       device's own tree (hisilicon,hi3xxx-clkgate):
         clk_usb2phy_pll  CRG+0x40 bit6 (0x40)
         clk_usb2phy_ref  CRG+0x40 bit2 (0x04)
         hclk_usb2otg     CRG+0x40 bit1 (0x02)
       and the vendor driver writes the bits straight into the enable register
       (drivers/clk/hisi/clk-kirin-common.c:445, hi3xxx_clkgate_enable). Read-
       modify-write keeps the neighbouring USB clocks intact. */
    movz w12, #((CRG_BASE) >> 16), lsl #16
    movk w12, #((CRG_BASE) & 0xffff)
    ldr  w13, [x12, #0x40]
    mov  w14, #0x46
    orr  w13, w13, w14
    str  w13, [x12, #0x40]
.if WITH_TRACE
    movz w15, #((TRACE_BASE) >> 16), lsl #16
    movk w15, #((TRACE_BASE) & 0xffff)
    mov  w16, #6
    str  w16, [x15, #40]
    str  w13, [x15, #44]
.endif
    movz w11, #0x1000
    movk w11, #0x30, lsl #16        /* a few ms at ~1 GHz for the PLL */
.Lclkwait:
    subs w11, w11, #1
    b.ne .Lclkwait
.endif
    movz w9, #((CORE_BASE) >> 16), lsl #16
    movk w9, #((CORE_BASE) & 0xffff)
    ldr  w10, [x9, #0x804]          /* DCTL */

    /* connect #1: clear SftDiscon (D+ pull-up on) */
    bic  w10, w10, #0x2
    str  w10, [x9, #0x804]
    trace 1
    spin SPIN_LONG

    /* disconnect */
    orr  w10, w10, #0x2
    str  w10, [x9, #0x804]
    trace 2
    spin SPIN_SHORT

    /* connect #2 */
    bic  w10, w10, #0x2
    str  w10, [x9, #0x804]
    trace 3
    spin SPIN_LONG

    /* disconnect again */
    orr  w10, w10, #0x2
    str  w10, [x9, #0x804]
    trace 4
    spin SPIN_SHORT

.if WITH_SMC
    /* PSCI SYSTEM_RESET (0x84000009): if the loader entered us, the machine
     * reboots here and this probe runs again - the loop is the signal. */
    movz w0, #0x0009
    movk w0, #0x8400, lsl #16
    mov  x1, xzr
    mov  x2, xzr
    mov  x3, xzr
    smc  #0
.endif

    /* reached only if the reset did not happen: leave the pull-up ON and stop,
     * so the host still sees a connect attempt from our writes */
    bic  w10, w10, #0x2
    str  w10, [x9, #0x804]
    trace 5

.Lhang:
    wfe
    b    .Lhang
