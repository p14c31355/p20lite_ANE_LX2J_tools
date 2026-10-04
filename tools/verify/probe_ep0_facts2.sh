#!/bin/bash
cd ~/dev/hi6250-src/drivers/usb/susb || exit 1

echo "=== dwc_otg_read_setup_packet (3237-3275) ==="
sed -n '3237,3275p' dwc_otg_cil.c

echo
echo "=== device register base (in_ep_regs / out_ep_regs assignment) ==="
grep -n "in_ep_regs\[i\]\s*=\|out_ep_regs\[i\]\s*=\|dev_if->in_ep_regs\|DWC_DEVICE_REG_OFFSET\|device_regs\b" dwc_otg_cil.c | head -12

echo
echo "=== the device base define ==="
grep -rn "define DWC_DEVICE_REG_OFFSET\|define DWC_INEP_REG_OFFSET\|define DWC_OUTEP_REG_OFFSET\|define DWC_DEVICE_REG_SIZE\|define DWC_EP_REG_OFFSET" *.h | head -8
