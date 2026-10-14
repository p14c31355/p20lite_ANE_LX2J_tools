#!/bin/bash
cd ~/dev/hi6250-src/drivers/usb/susb || exit 1

echo "=== device if regs init (105-130) ==="
sed -n '105,130p' dwc_otg_cil.c

echo
echo "=== ep0_activate rest (3275-3330) ==="
sed -n '3275,3330p' dwc_otg_cil.c

echo
echo "=== where diepctl.epena / xfersize is set (start IN transfer) ==="
grep -n "\.b\.epena = 1\|\.b\.xfersize\|\.b\.pktcnt\|\.b\.txfnum" dwc_otg_cil.c | head -20

echo
echo "=== write_packet head ==="
sed -n '4820,4860p' dwc_otg_cil.c
