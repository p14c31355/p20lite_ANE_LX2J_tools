#!/bin/bash
cd ~/dev/hi6250-src || exit 1

echo "=== data_fifo base (cil.c 158-168) ==="
sed -n '158,168p' drivers/usb/susb/dwc_otg_cil.c

echo
echo "=== depctl_data union (regs.h) ==="
N=$(grep -n "typedef union depctl_data" drivers/usb/susb/dwc_otg_regs.h | head -1 | cut -d: -f1)
sed -n "${N},$((N+45))p" drivers/usb/susb/dwc_otg_regs.h

echo
echo "=== deptsiz_data union ==="
N=$(grep -n "typedef union deptsiz_data" drivers/usb/susb/dwc_otg_regs.h | head -1 | cut -d: -f1)
sed -n "${N},$((N+30))p" drivers/usb/susb/dwc_otg_regs.h

echo
echo "=== modern dwc2 gadget: start_req IN order (slave writes fifo before epena?) ==="
grep -n "dwc2_hsotg_start_req\|dwc2_hsotg_write_fifo" drivers/usb/dwc2/gadget.c | head -8
