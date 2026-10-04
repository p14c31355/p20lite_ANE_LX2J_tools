#!/bin/bash
cd ~/dev/hi6250-src || exit 1

echo "=== the slave branch after DMA (3935-4005) ==="
sed -n '3935,4005p' drivers/usb/susb/dwc_otg_cil.c

echo
echo "=== write_packet definition ==="
grep -n "^void dwc_otg_write_packet\|dwc_otg_write_packet(dwc" drivers/usb/susb/dwc_otg_cil.c | head -4

echo
echo "=== global regs struct order (grxsts offsets) ==="
N=$(grep -n "typedef struct dwc_otg_core_global_regs" drivers/usb/susb/dwc_otg_regs.h | head -1 | cut -d: -f1)
sed -n "${N},$((N+42))p" drivers/usb/susb/dwc_otg_regs.h

echo
echo "=== doepint union (setup bit) ==="
N=$(grep -n "typedef union doepint_data" drivers/usb/susb/dwc_otg_regs.h | head -1 | cut -d: -f1)
sed -n "${N},$((N+30))p" drivers/usb/susb/dwc_otg_regs.h
