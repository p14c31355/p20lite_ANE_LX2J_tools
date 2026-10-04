#!/bin/bash
cd ~/dev/hi6250-src/drivers/usb/susb || exit 1
echo "=== force_dev_mode / devspd / utmi in the tree ==="
grep -rn "force_dev_mode\|force_devmode\|devspd\|dev_speed\|DCFG_DEVSPD\|utmi16\|utmi_16\|ulpi_utmi_sel\|phyif" *.c *.h 2>/dev/null | grep -v "^Binary" | head -25
echo
echo "=== gusbcfg writes in the hi6250 glue ==="
grep -n "gusbcfg" dwc_otg_hi6250.c dwc_otg_hicommon.c 2>/dev/null | head -10
echo
echo "=== dwc_otg_enable_device / pcd init sequence refs ==="
grep -n "dwc_otg_enable_device\|EnableDevice\|softdisconnect\|soft_disconnect" dwc_otg_pcd.c dwc_otg_cil.c 2>/dev/null | head -15
