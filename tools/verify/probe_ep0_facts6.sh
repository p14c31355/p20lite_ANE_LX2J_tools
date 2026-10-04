#!/bin/bash
cd ~/dev/hi6250-src || exit 1

echo "=== DATA_FIFO offset defines ==="
grep -rn "DWC_OTG_DATA_FIFO_OFFSET\|DWC_OTG_DATA_FIFO_SIZE\|DWC_OTG_DATA_FIFO" drivers/usb/susb/dwc_otg_os_dep.h drivers/usb/susb/dwc_otg_regs.h drivers/usb/susb/dwc_otg_cil.h 2>/dev/null | grep define | head -6

echo
echo "=== depctl union rest (bits after eptype) ==="
N=$(grep -n "typedef union depctl_data" drivers/usb/susb/dwc_otg_regs.h | head -1 | cut -d: -f1)
sed -n "$((N+45)),$((N+95))p" drivers/usb/susb/dwc_otg_regs.h

echo
echo "=== ep_start_transfer IN branch (3860-3935) ==="
sed -n '3860,3935p' drivers/usb/susb/dwc_otg_cil.c

echo
echo "=== write_packet (FIFO push) 4850-4900 ==="
sed -n '4850,4900p' drivers/usb/susb/dwc_otg_cil.c
