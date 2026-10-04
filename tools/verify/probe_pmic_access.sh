#!/bin/bash
# Find how the PMIC window is addressed: is register N at (base + N) or (base + N*4)?
cd ~/dev/hi6250-src || exit 1

echo "=== files mentioning hisilicon,hisi-pmic ==="
grep -rln 'hisilicon,hisi-pmic' --include=*.c drivers/ 2>/dev/null | head -5
grep -rln 'hisi-pmic' --include=*.c drivers/ 2>/dev/null | head -8

echo
echo "=== the hisi_pmic_reg_read/write callers' headers (where is it declared?) ==="
grep -rn 'hisi_pmic_reg_read' --include=*.h . 2>/dev/null | head -5
grep -rn 'hisi_pmic_reg_write\|hisi_pmic_reg_read' --include=*.c drivers/clk/hisi/clk-kirin-common.c | head -3

echo
echo "=== the clk driver's pmuctrl iomap usage: any offset math? ==="
grep -n 'pmu_clk_enable\|pmuctrl\|gdata\[0\]\|gdata\[1\]' drivers/clk/hisi/clk-kirin-common.c | head -20

echo
echo "=== the blackbox adapter's pmic calls (context) ==="
grep -n -B4 -A2 'hisi_pmic_reg_read\|hisi_pmic_reg_write' drivers/hisi/mntn/blackbox/platform_ap/rdr_hisi_ap_adapter.c | head -30
