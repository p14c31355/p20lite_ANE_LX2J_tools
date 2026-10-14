#!/bin/bash
cd ~/dev/hi6250-src/drivers/usb/susb || exit 1

echo "=== the region offset defines ==="
grep -rn "DWC_DEV_GLOBAL_REG_OFFSET\|DWC_DEV_IN_EP_REG_OFFSET\|DWC_DEV_OUT_EP_REG_OFFSET\|DWC_DATA_FIFO_OFFSET\|DWC_DATA_FIFO_SIZE" *.h *.c | head -10

echo
echo "=== in-ep register struct (diepctl/dieptsiz order) ==="
N=$(grep -n "struct dwc_otg_dev_in_ep_regs" dwc_otg_regs.h | head -1 | cut -d: -f1)
echo "at $N"
sed -n "${N},$((N+16))p" dwc_otg_regs.h

echo
echo "=== out-ep register struct ==="
N=$(grep -n "struct dwc_otg_dev_out_ep_regs" dwc_otg_regs.h | head -1 | cut -d: -f1)
echo "at $N"
sed -n "${N},$((N+16))p" dwc_otg_regs.h

echo
echo "=== device global register struct ==="
N=$(grep -n "struct dwc_otg_device_global_regs" dwc_otg_regs.h | head -1 | cut -d: -f1)
echo "at $N"
sed -n "${N},$((N+22))p" dwc_otg_regs.h

echo
echo "=== data fifo base assignment ==="
grep -n "data_fifo\[" dwc_otg_cil.c | head -6
grep -rn "data_fifo\[i\] =\|data_fifo\[0\] =" dwc_otg_cil.c | head -4
