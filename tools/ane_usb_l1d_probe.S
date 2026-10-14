/* L1 USB probe for the ANE-LX2J: bring the USB2 controller up from the state
 * the loader left it in, then attach. This is the sequence the vendor kernel
 * itself runs, taken from the tree that matches this SoC:
 *
 *   drivers/usb/susb/dwc_otg_hi6250.c   init_usb_otg_phy_hi6250()
 *   drivers/usb/susb/dwc_otg_hi6250.h   the PERI_CRG_* / BIT_RST_* constants
 *   drivers/usb/susb/hisi_usb_otg_type.h the usbotg2_ctrl0/2/3 bit layouts
 *   drivers/clk/hisi/clk-kirin-common.c hi3xxx_clkgate_enable (enable write)
 *   the device's own tree: gate reg/bits, pctrl offset, eye pattern values
 *
 * Sequence (all from the sources above):
 *   1  CRG+0x40 |= pll|ref|hclk            clocks the PHY and OTG (DT gates)
 *   2  PCTRL+0x64: bits 24-26 = 5          config the abb clock
 *   3  CRG+0x94 |= ADP|32K|MUX|AHBIF       release the AHBIF resets
 *   4  AHBIF+0x00 |= acaenb_sel|id_sel      ctrl0: id from PHY's iddig
 *   5  AHBIF+0x0C = 0x06b866db             ctrl3: device eye pattern (DT)
 *   6  CRG+0x94 |= PHYPOR   delay          release the PHY power-on reset
 *   7  CRG+0x94 |= PHY      delay          release the PHY clock domain
 *   8  CRG+0x94 |= OTG                     release the OTG reset
 *   9  AHBIF+0x08 |= vbusvldsel|vbusvldext ctrl2: VBUS valid from register
 *  10  DCTL.SftDiscon cleared              attach: the host should see a device
 *  15  SCTRL+0x30: AP PPLL0 enable+lock     the root of the USB2PHY clock chain
 *  16  SCTRL+0x30 read back                 (post-enable state)
 *  21  GUSBCFG read back                    what the core reports after attach
 *  22  DCFG read back
 *  23  DCTL read back                       is SftDiscon really cleared?
 *  24  GINTSTS read back
 *  17  USB2PHY +0x00 read                   first touch of the PHY block itself
 *  18  USB2PHY +0x04 read                   (0xfe000000; read-only, after gates)
 *  19  USB2PHY +0x08 read
 *  20  USB2PHY +0x0C read
 *
 * The earlier probe wrote only the clock gates and DCTL; the host saw nothing.
 * This one follows the vendor bring-up, so an attach here means the controller
 * is alive and the USB is ours to use as an observation channel.
 *
 * Ends halted with the pull-up ON (no reset): the attached device is then
 * stable on the host for as long as inspection needs. Build variants:
 *   WITH_SMC=1 adds the PSCI reset loop instead (used when a live loop is
 *   wanted); the device recovery is a power-button press either way.
 */
.section .text, "ax"
.balign 4
.global _start

/* record [step, w10] into the trace array; empty on the device */
.macro trace step
.if WITH_TRACE
    movz w15, #((TRACE_BASE) >> 16), lsl #16
    movk w15, #((TRACE_BASE) & 0xffff)
    mov  w16, #\step
    str  w16, [x15, #(8 * (\step - 1))]
    str  w10, [x15, #(8 * (\step - 1) + 4)]
.endif
.endm

/* busy-wait w11 cycles (clobbers w11 and flags only) */
.macro spin count
    movz w11, #((\count >> 16) & 0xffff)
    movk w11, #((\count >> 32) & 0xffff), lsl #16
9:  subs w11, w11, #1
    b.ne 9b
.endm

_start:
    /* MMU off: the loader leaves it on with tables that do not cover these
       registers (measured; the first version of the USB probe was silent). */
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

.if WITH_ABB
    /* The abb gate for the USB PHY's parent clock (clk_abb_192). Decoded from
       the device's tree and drivers/clk/hisi/clk-kirin-common.c:
         - the DT's hisilicon,clkgate 0x0000010F_00000000 gives
           pmu_clk_enable = 0x010F (PMIC register), ebits = BIT(0),
         - and hi3xxx_multicore_abb_clkgate_prepare() (line 1100, with
           AP_ABB_EN = 0, LPM3_ABB_EN = 1, ABB_SCBAKDATA = SCBAKDATA12 =
           sysctrl 0xfff0a000 + 0x43C) does:
             if AP_ABB_EN clear:
                 if LPM3_ABB_EN clear: PMIC 0x010F |= ebits
                 set AP_ABB_EN
             mdelay(1)
       The hwspinlock in the vendor code serialises this against the other
       cores; a bare payload runs alone, so it is skipped. */
    movz x9, #((PMIC_BASE) >> 16), lsl #16
    movk x9, #((PMIC_BASE) & 0xffff)
    movz x13, #((SCTRL_BASE) >> 16), lsl #16
    movk x13, #((SCTRL_BASE) & 0xffff)
    ldr  w10, [x13, #0x43C]
    tbnz w10, #0, .Labb_done         /* AP_ABB_EN (bit0) already set */
    tbnz w10, #1, .Labb_set          /* LPM3_ABB_EN (bit1): skip only the PMIC write */
    ldrb w12, [x9, #0x10F]
    orr  w12, w12, #0x1
    strb w12, [x9, #0x10F]
.Labb_set:
    ldr  w10, [x13, #0x43C]
    orr  w10, w10, #0x1
    str  w10, [x13, #0x43C]
    spin SPIN_US                     /* the vendor's mdelay(1) before use */
.Labb_done:
.if WITH_TRACE
    movz w15, #((TRACE_BASE) >> 16), lsl #16
    movk w15, #((TRACE_BASE) & 0xffff)
    mov  w16, #11
    str  w16, [x15, #80]
    str  w10, [x15, #84]
.endif
.endif

    /* 15/16: AP PPLL0 - the root of the USB2PHY clock chain.
       clk_usb2phy_pll's parent is clkfac_usb2phy (a fixed /60) whose parent is
       clk_ap_ppll0, a "hisilicon,ppll-ctrl" clock whose DT node lives under
       sctrl@0xfff0a000 (the window this probe already uses for the abb gate).
       clk-kirin-common.c: PPLLCTRL0(n) = 0x030 + n*8, bit0 = EN, bit26 = LOCK,
       and the enable path sets EN then polls LOCK (AP_PPLL_STABLE_TIME). If the
       loader left the ppll off, every usb2phy gate downstream is clocking
       nothing. Bounded poll; on QEMU the lock bit never appears and the loop
       just expires. x13 is set here rather than inherited from the abb block. */
    movz x13, #((SCTRL_BASE) >> 16), lsl #16
    movk x13, #((SCTRL_BASE) & 0xffff)
    ldr  w10, [x13, #0x30]
    trace 15
    orr  w10, w10, #0x1                 /* EN */
    str  w10, [x13, #0x30]
    mov  w14, #0x400
.Lppll0_wait:
    ldr  w10, [x13, #0x30]
    tbnz w10, #26, .Lppll0_done         /* LOCK */
    subs w14, w14, #1
    b.ne .Lppll0_wait
.Lppll0_done:
    ldr  w10, [x13, #0x30]
    trace 16

    /* 1: clocks - CRG+0x40 |= 0x46 (pll bit6, ref bit2, hclk bit1) */
    movz x12, #((CRG_BASE) >> 16), lsl #16
    movk x12, #((CRG_BASE) & 0xffff)
    ldr  w10, [x12, #0x40]
    mov  w14, #0x46
    orr  w10, w10, w14
    str  w10, [x12, #0x40]
    trace 1

    /* 2: abb clock config - PCTRL+0x64 bits 24-26 = 5 */
    movz x13, #((PCTRL_BASE) >> 16), lsl #16
    movk x13, #((PCTRL_BASE) & 0xffff)
    ldr  w10, [x13, #0x64]
    mov  w14, #0x7
    lsl  w14, w14, #24
    bic  w10, w10, w14
    mov  w14, #0x5
    lsl  w14, w14, #24
    orr  w10, w10, w14
    str  w10, [x13, #0x64]
    trace 2

    /* 3: AHBIF resets released - CRG+0x94 |= ADP(27)|32K(14)|MUX(10)|AHBIF(11) */
    ldr  w10, [x12, #0x94]
    mov  w14, #0x1
    lsl  w14, w14, #27
    orr  w10, w10, w14
    mov  w14, #0x1
    lsl  w14, w14, #14
    orr  w10, w10, w14
    mov  w14, #0x1
    lsl  w14, w14, #10
    orr  w10, w10, w14
    mov  w14, #0x1
    lsl  w14, w14, #11
    orr  w10, w10, w14
    str  w10, [x12, #0x94]
    trace 3

    /* 4: ctrl0 - acaenb_sel(2)|id_sel(4) = 0x14 */
    movz x13, #((AHBIF_BASE) >> 16), lsl #16
    movk x13, #((AHBIF_BASE) & 0xffff)
    ldr  w10, [x13, #0x00]
    mov  w14, #0x14
    orr  w10, w10, w14
    str  w10, [x13, #0x00]
    trace 4

    /* 5: ctrl3 - the device eye pattern from the device tree (0x06b866db) */
    movz w10, #0x66db
    movk w10, #0x06b8, lsl #16
    str  w10, [x13, #0x0C]
    trace 5

    /* 6: release PHY power-on reset, then wait */
    ldr  w10, [x12, #0x94]
    mov  w14, #0x1
    lsl  w14, w14, #13
    orr  w10, w10, w14
    str  w10, [x12, #0x94]
    trace 6
    spin SPIN_US

    /* 7: release PHY clock domain, then wait */
    ldr  w10, [x12, #0x94]
    mov  w14, #0x1
    lsl  w14, w14, #12
    orr  w10, w10, w14
    str  w10, [x12, #0x94]
    trace 7
    spin SPIN_US

    /* 8: release OTG */
    ldr  w10, [x12, #0x94]
    mov  w14, #0x1
    lsl  w14, w14, #9
    orr  w10, w10, w14
    str  w10, [x12, #0x94]
    trace 8

    /* 9: ctrl2 - vbusvldsel(2)|vbusvldext(3) = 0x0C */
    ldr  w10, [x13, #0x08]
    mov  w14, #0x0C
    orr  w10, w10, w14
    str  w10, [x13, #0x08]
    trace 9
    spin SPIN_MS

    /* 9.5: DWC2 core - pin it to device mode and give it a clean start.
       Source: the vendor's old dwc_otg CIL (drivers/usb/susb/dwc_otg_cil.c
       around lines 1300-1420): for an HS UTMI+ PHY it clears ulpi_utmi_sel
       and sets phyif to the PHY width (0 = 8 bit), then does a core soft
       reset whose AHB-idle and self-clear conditions it polls; init_devspd()
       programs DCFG.DevSpd (0 = high speed). GUSBCFG.ForceDevMode (bit 30)
       pins the role: the loader's fastboot ran the core in device mode, but a
       core left in host mode never pulls up, and nothing guarantees the state
       across the loader's reboot. Waits are bounded so an unresponsive
       controller cannot hang the probe (QEMU lands here with zeroed
       "registers", which is exactly the bounded-wait path). */
.if WITH_CORE
    movz x13, #((CORE_BASE) >> 16), lsl #16
    movk x13, #((CORE_BASE) & 0xffff)
    ldr  w10, [x13, #0x00C]
    mov  w14, #0x4000
    lsl  w14, w14, #16                  /* bit 30: force device mode */
    orr  w10, w10, w14
    bic  w10, w10, #0x18                /* UTMI+ 8-bit: clear utmi_sel|phyif */
    str  w10, [x13, #0x00C]
    trace 12
    mov  w14, #0x1000
.Lahb:
    ldr  w10, [x13, #0x010]
    tbnz w10, #31, .Lrst
    subs w14, w14, #1
    b.ne .Lahb
.Lrst:
    ldr  w10, [x13, #0x010]
    orr  w10, w10, #0x1
    str  w10, [x13, #0x010]
    mov  w14, #0x1000
.Lrstw:
    ldr  w10, [x13, #0x010]
    tbz  w10, #0, .Lrst_done
    subs w14, w14, #1
    b.ne .Lrstw
.Lrst_done:
    /* The soft reset resets the PHY/role selection too: the kernel's
       dwc2_core_reset() re-writes GUSBCFG (force-device) after EVERY reset,
       and dwc2_hs_phy_init() resets right after setting the PHY parameters
       - so the order that matches the upstream driver is
       (reset) -> GUSBCFG -> (settle) -> DCFG.
       Source: drivers/usb/dwc2/core.c (dwc2_core_reset, dwc2_hs_phy_init). */
    ldr  w10, [x13, #0x00C]
    mov  w14, #0x4000
    lsl  w14, w14, #16                  /* bit 30: force device mode */
    orr  w10, w10, w14
    bic  w10, w10, #0x18                /* UTMI+ 8-bit: clear utmi_sel|phyif */
    str  w10, [x13, #0x00C]
    trace 14
    spin SPIN_MS                        /* the kernel settles 150-200ms here */
    ldr  w10, [x13, #0x800]             /* DCFG: devspd = high speed, addr 0 */
    bic  w10, w10, #0x3
    str  w10, [x13, #0x800]
    trace 13
.endif

    /* 10: attach - clear DCTL.SftDiscon (bit 1), then hold */
    movz x12, #((CORE_BASE) >> 16), lsl #16
    movk x12, #((CORE_BASE) & 0xffff)
    ldr  w10, [x12, #0x804]
    bic  w10, w10, #0x2
    str  w10, [x12, #0x804]
    trace 10
    spin SPIN_MS                        /* let the connect settle */

    /* 21-24: post-attach readbacks - what the core reports now. DCTL is the
       critical one: if SftDiscon did not stay cleared, there is nothing the
       PHY can do and the host is right to see silence. */
    ldr  w10, [x12, #0x00C]
    trace 21                            /* GUSBCFG */
    ldr  w10, [x12, #0x800]
    trace 22                            /* DCFG */
    ldr  w10, [x12, #0x804]
    trace 23                            /* DCTL */
    ldr  w10, [x12, #0x014]
    trace 24                            /* GINTSTS */

    /* 17-20: the USB2PHY block (0xfe000000) - read-only, first touch of it.
       The gates opened in step 1 are this block's clocks (clk_usb2phy_pll/ref
       are its DT clock nodes), so it should answer; a hang here happens after
       the attach, so the host-visible signal and the trace up to 24 are
       already secured either way. */
    movz x14, #((PHY_BASE) >> 16), lsl #16
    movk x14, #((PHY_BASE) & 0xffff)
    ldr  w10, [x14, #0x0]
    trace 17
    ldr  w10, [x14, #0x4]
    trace 18
    ldr  w10, [x14, #0x8]
    trace 19
    ldr  w10, [x14, #0xC]
    trace 20

    spin SPIN_LONG

.if WITH_SMC
    movz w0, #0x0009
    movk w0, #0x8400, lsl #16
    mov  x1, xzr
    mov  x2, xzr
    mov  x3, xzr
    smc  #0
.endif

    /* stay attached: the host sees a stable device to inspect */
.Lhalt:
    wfe
    b    .Lhalt
