#!/bin/bash
cd ~/dev/hi6250-src || exit 1
echo "=== ABB_SCBAKDATA / AP_ABB_EN / LPM3_ABB_EN definitions ==="
grep -rn "ABB_SCBAKDATA\|AP_ABB_EN\|LPM3_ABB_EN" --include=*.h --include=*.c drivers/clk/hisi/ | grep -E "define|=" | head -12
echo
echo "=== the sysctrl node in the ANE DT (base) ==="
cd /home/placeless/dev/p20-root || exit 1
grep -iE "sysctrl|sctrl" firmware/ane_dtb/fdt_properties.txt | awk -F'\t' '{print $1" | "$2" | "$3}' | head -12
