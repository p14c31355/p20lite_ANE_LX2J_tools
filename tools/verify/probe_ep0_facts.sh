#!/bin/bash
# Extract the EP0 programming facts for a bare-metal DWC2 device responder.
# Sources: the vendor's old dwc_otg driver (susb/) that runs on this SoC.
cd ~/dev/hi6250-src/drivers/usb/susb || exit 1

echo "=== EP0 activation / setup packet read (pcd / cil) ==="
grep -n "ep0_activate\|ep0_start\|activate_ep\|depctl\|diepctl\|doepctl" dwc_otg_cil.c | head -20

echo
echo "=== the rx fifo pop / setup read helper ==="
grep -n "dwc_otg_read_setup_packet\|read_setup_packet\|rx_fifo\|dwc_otg_read_packet" dwc_otg_cil.c dwc_otg_cil.h 2>/dev/null | head -15

echo
echo "=== dieptsiz / doep tsiz struct fields ==="
grep -n "typedef union dieptsiz\|typdef union dieptsiz\|dieptsiz_data\|doeptsiz_data" dwc_otg_regs.h | head -5
