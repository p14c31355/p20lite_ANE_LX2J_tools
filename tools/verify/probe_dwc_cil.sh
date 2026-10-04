#!/bin/bash
cd ~/dev/hi6250-src/drivers/usb/susb || exit 1
echo "=== core reset / init in the CIL ==="
grep -n "CSftRst\|csftrst\|AHBIdle\|ahbidle\|RxFifoFlush\|ForceDevMode\|forcedevmode\|force_dev" dwc_otg_cil.c | head -20
echo
echo "=== gusbcfg_data union ==="
N=$(grep -n "gusbcfg_data" dwc_otg_regs.h | head -1 | cut -d: -f1)
echo "at line $N"
sed -n "${N},$((N+45))p" dwc_otg_regs.h
