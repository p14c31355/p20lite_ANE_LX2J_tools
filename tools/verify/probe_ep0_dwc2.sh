#!/bin/bash
cd ~/dev/hi6250-src/drivers/usb/dwc2 || exit 1
echo "=== ep0 start_trans / dieptsiz usage in the modern dwc2 gadget ==="
grep -n "dieptsiz\|DIEPTSIZ0\|dwc2_hsotg_ep0_start" gadget.c debugfs.c 2>/dev/null | head -20
echo
N=$(grep -n "static void dwc2_hsotg_ep0_start_trans" gadget.c | head -1 | cut -d: -f1)
echo "ep0_start_trans at $N"
[ -n "$N" ] && sed -n "${N},$((N+40))p" gadget.c
echo
echo "=== the setup read + setup handling (grep) ==="
grep -n "DOEPINT_SETUP\|setup_received\|dwc2_hsotg_setup_status\|GEINMSK_SETUP" gadget.c | head -10
