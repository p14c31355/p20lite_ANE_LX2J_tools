/* L2 USB probe: an EP0 responder - enough enumeration to become a real
 * USB device, written from the two drivers that ran this controller.
 *
 * Earlier levels only pulled the D+ line up (L1c). An attached but mute
 * device is still invisible: the host sends SETUP and gets nothing back.
 * This probe answers control transfers in slave (PIO) mode:
 *
 *   - SETUP reception and the RX-FIFO status drain follow
 *     s3c_hsotg_handle_rx() (drivers/usb/dwc2/gadget.c): the core pushes a
 *     status entry into the RX FIFO and raises GINTSTS.RXFLVL; the entry is
 *     popped by reading GRXSTSP, SETUPRX (6) carries 8 bytes of setup packet,
 *     which are then read from the data FIFO.
 *   - Transfer start follows s3c_hsotg_start_req(): [DIEPTSIZ0 =
 *     xfersize | pktcnt<<19] -> [DIEPCTL0 |= epena|cnak|usbactep] -> then the
 *     packet words are written into the FIFO (slave mode writes the FIFO in
 *     software; there is no DMA here).
 *   - Bit positions are from drivers/usb/dwc2/hw.h and the vendor's
 *     dwc_otg_regs.h depctl_data union (epena 31, epdis 30, cnak 26,
 *     stall 21, usbactep 15; DCTL cgnpinnak 8, sftdiscon 1).
 *   - The post-reset GUSBCFG re-write mirrors dwc2_core_reset() in
 *     drivers/usb/dwc2/core.c: the soft reset resets the PHY/role selection,
 *     so GUSBCFG is re-programmed after every reset, before DCFG.
 *
 * Device presented: vendor-specific (class 0xff), one interface, zero
 * endpoints - the smallest thing a host will happily enumerate and bind no
 * driver to. VID 0x12d1/PID 0x0001. Descriptors live in the last words of
 * this file. Requests we do not implement are STALLed, which is the
 * protocol-correct answer.
 *
 * Built with the same two variants as L1: a traced emulated build whose
 * register writes can be dumped from QEMU (the responder loop simply spins
 * there, since QEMU has no DWC2), and a device build that never returns -
 * so the loader's watchdog recycles it through fastboot, which the night
 * runner captures, exactly like the other hang-type probes.
 *
 * All bases arrive as --defsym values; there are deliberately no .set
 * defaults here (a .set would override the command line and the emulated
 * build would silently write the device's addresses).
 */

/* one trace entry: [step, value] at TRACE_BASE + 8*(step-1) */
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
    /* abb gate for the USB PHY's parent clock (clk_abb_192), decoded from
       the DT's hisilicon,clkgate and clk-kirin-common.c
       (hi3xxx_multicore_abb_clkgate_prepare, line 1100):
       AP_ABB_EN = bit0, LPM3_ABB_EN = bit1, ABB_SCBAKDATA12 = sctrl+0x43C. */
    movz x9, #((PMIC_BASE) >> 16), lsl #16
    movk x9, #((PMIC_BASE) & 0xffff)
    movz x13, #((SCTRL_BASE) >> 16), lsl #16
    movk x13, #((SCTRL_BASE) & 0xffff)
    ldr  w10, [x13, #0x43C]
    tbnz w10, #0, .Labb_done         /* AP_ABB_EN already set */
    tbnz w10, #1, .Labb_set          /* LPM3_ABB_EN: skip only the PMIC write */
    ldrb w12, [x9, #0x10F]
    orr  w12, w12, #0x1
    strb w12, [x9, #0x10F]
.Labb_set:
    ldr  w10, [x13, #0x43C]
    orr  w10, w10, #0x1
    str  w10, [x13, #0x43C]
    spin SPIN_US
.Labb_done:
    trace 11
.endif

    /* 1: clocks - CRG+0x40 |= 0x46 (pll, ref, hclk) */
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

    /* 5: ctrl3 - the device eye pattern from the device tree */
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

    /* 9.5: core - device mode, clean start, then re-assert GUSBCFG.
       Source: drivers/usb/dwc2/core.c. dwc2_hs_phy_init() writes the PHY
       parameters and then soft-resets the core ("Reset after setting the PHY
       parameters"); dwc2_core_reset() itself re-writes GUSBCFG force-mode
       right after the reset self-cleans. Hence: GUSBCFG -> reset ->
       GUSBCFG -> settle -> DCFG. */
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
    ldr  w10, [x13, #0x00C]
    mov  w14, #0x4000
    lsl  w14, w14, #16
    orr  w10, w10, w14
    bic  w10, w10, #0x18
    str  w10, [x13, #0x00C]
    trace 14
    spin SPIN_MS
    ldr  w10, [x13, #0x800]             /* DCFG: devspd = high speed, addr 0 */
    bic  w10, w10, #0x3
    str  w10, [x13, #0x800]
    trace 13

    /* 9.6: device-mode plumbing before the pull-up.
       CGNPINNAK (DCTL bit8): NAK, never STALL, non-periodic IN endpoints
       whose FIFO runs empty - the vendor's ep0_activate() sets it, and a
       control responder that STALLs a truncated IN phase confuses hosts.
       DIEPCTL0.mps = 64B (the HS control packet size; vendor ep0_activate
       picks it from DSTS.EnumSpd, 0 for high speed). */
    ldr  w10, [x13, #0x804]
    orr  w10, w10, #0x100              /* cgnpinnak */
    str  w10, [x13, #0x804]
    trace 15
    ldr  w10, [x13, #0x900]
    bic  w10, w10, #0x3                /* mps bits 1:0 = 0 -> 64 bytes */
    str  w10, [x13, #0x900]
    trace 16

    /* 10: attach - clear DCTL.SftDiscon (bit 1), then hold */
    ldr  w10, [x13, #0x804]
    bic  w10, w10, #0x2
    str  w10, [x13, #0x804]
    trace 10
    spin SPIN_LONG

    /* ================= EP0 responder =================
       Register map used below (device offsets on CORE_BASE):
         0x014 GINTSTS   0x020 GRXSTSP   0x1000 FIFO0 (data)
         0x800 DCFG      0x804 DCTL      0x900 DIEPCTL0
         0x908 DIEPINT0  0x910 DIEPTSIZ0

       x13 = CORE_BASE throughout.  x0 = data pointer, w1 = length,
       w19 = wLength of the current setup, w20/w21 = pending address state. */
    mov  w10, #0
    trace 17
    mov  w21, #0

.Lloop:
    ldr  w10, [x13, #0x014]             /* GINTSTS: RXFLVL (bit4)? */
    tbz  w10, #4, .Lloop
    ldr  w10, [x13, #0x020]             /* GRXSTSP: pop a status entry */
    mov  w11, w10
    lsr  w11, w11, #17
    and  w11, w11, #0xF                 /* PKTSTS */
    cmp  w11, #6                        /* SETUPRX? */
    b.ne .Ldrain

    /* -- setup packet: 8 bytes, two words from FIFO0 -- */
    ldr  w14, [x13, #0x1000]            /* bmRequestType, bRequest, wValue */
    ldr  w15, [x13, #0x1000]            /* wIndex, wLength */
    lsr  w19, w15, #16                  /* wLength */
    and  w16, w14, #0xFF                /* bmRequestType */
    ubfx w17, w14, #8, #8               /* bRequest */
    cmp  w16, #0x80                     /* device-to-host, standard? */
    b.ne .Lnot_d2h
    cmp  w17, #6                        /* GET_DESCRIPTOR */
    b.ne .Lstall
    ubfx w18, w14, #16, #16
    lsr  w18, w18, #8                   /* descriptor type */
    cmp  w18, #1
    b.eq .Ls_desc_dev
    cmp  w18, #2
    b.eq .Ls_desc_cfg
    b    .Lstall

.Ls_desc_dev:
    adr  x0, dev_desc
    mov  w1, #18
    b    .Lsend
.Ls_desc_cfg:
    adr  x0, cfg_desc
    mov  w1, #18
    b    .Lsend

.Lnot_d2h:
    cbnz w16, .Lstall                   /* only standard host-to-device */
    cmp  w17, #5                        /* SET_ADDRESS */
    b.eq .Ls_addr
    cmp  w17, #9                        /* SET_CONFIGURATION */
    b.eq .Ls_status
    b    .Lstall

.Ls_addr:
    /* The address applies after the status stage completes: remember it,
       ack, and program DCFG once DIEPINT0.xfercompl says the ack went out
       (s3c_hsotg applies set_address after the status stage as well). */
    ubfx w20, w14, #16, #16
    and  w20, w20, #0x7F
    mov  w21, #1
.Ls_status:
    mov  x0, xzr
    mov  w1, #0
    b    .Lsend

.Lstall:
    ldr  w11, [x13, #0x900]
    mov  w12, #0x20
    lsl  w12, w12, #16                  /* bit21 stall */
    orr  w11, w11, w12
    mov  w12, #0x0400
    lsl  w12, w12, #16                  /* bit26 cnak */
    orr  w11, w11, w12
    str  w11, [x13, #0x900]
    b    .Lloop

.Lsend:
    /* clamp data to the host's wLength */
    cmp  w1, w19
    csel w1, w1, w19, lo
    /* DIEPTSIZ0 = xfersize | pktcnt(1)<<19 */
    mov  w11, w1
    mov  w12, #1
    lsl  w12, w12, #19
    orr  w11, w11, w12
    str  w11, [x13, #0x910]
    /* DIEPCTL0 |= usbactep | cnak | epena  (order per s3c_hsotg_start_req) */
    ldr  w11, [x13, #0x900]
    orr  w11, w11, #0x8000              /* usbactep */
    mov  w12, #0x0400
    lsl  w12, w12, #16
    orr  w11, w11, w12                  /* cnak */
    mov  w12, #0x8000
    lsl  w12, w12, #16
    orr  w11, w11, w12                  /* epena */
    str  w11, [x13, #0x900]
    /* push the packet words into FIFO0 (slave mode: software writes) */
    cbz  w1, .Lsend_done
    add  w12, w1, #3
    lsr  w12, w12, #2
    add  x11, x0, x12, lsl #2
.Lpush:
    ldr  w14, [x0], #4
    str  w14, [x13, #0x1000]
    cmp  x0, x11
    b.lo .Lpush
.Lsend_done:
    cbz  w21, .Lloop                    /* no pending address: next setup */
    /* wait for the status stage of SET_ADDRESS to complete */
    mov  w12, #0x1000
.Lackw:
    ldr  w11, [x13, #0x908]             /* DIEPINT0 */
    tbnz w11, #0, .Lackdone             /* bit0 xfercompl */
    subs w12, w12, #1
    b.ne .Lackw
.Lackdone:
    mov  w11, #1
    str  w11, [x13, #0x908]             /* write-1-to-clear */
    ldr  w11, [x13, #0x800]             /* DCFG: install the address */
    bic  w11, w11, #0x7F0
    lsl  w12, w20, #4
    orr  w11, w11, w12
    str  w11, [x13, #0x800]
    mov  w21, #0
    b    .Lloop

.Ldrain:
    /* any non-setup status entry: drain its bytes so the FIFO keeps flowing
       (OUT data stages; a control-write status arrives with size 0) */
    ubfx w11, w10, #4, #11              /* bytecount */
    add  w11, w11, #3
    lsr  w11, w11, #2
    cbz  w11, .Lloop
.Ld_loop:
    ldr  w12, [x13, #0x1000]
    subs w11, w11, #1
    b.ne .Ld_loop
    b    .Lloop

    /* ---------------- descriptors (little-endian words) ----------------
       device: 12 01 00 02 | 00 00 00 40 | d1 12 01 00 | 01 00 00 00 | 00 01
         bLength 18, DEVICE, bcdUSB 2.00, class 0, mps0 64,
         idVendor 0x12d1, idProduct 0x0001, bcdDevice 0x0001,
         no strings, 1 configuration.
       config set: 09 02 12 00 | 01 01 00 80 | 32 | 09 04 00 00 | 00 ff 00 00 | 00
         config: 18 bytes total, 1 interface, value 1, bus powered, 100mA;
         interface: zero endpoints, class 0xff vendor-specific - the host
         binds no driver and keeps the port. */
    .align 3
dev_desc:
    .word 0x02000112, 0x40000000, 0x000112D1, 0x00000001, 0x00000100
cfg_desc:
    .word 0x00120209, 0x80000101, 0x00040932, 0x00FF0000, 0x00000000
