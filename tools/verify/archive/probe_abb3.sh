#!/bin/bash
# Where are AP_ABB_EN / LPM3_ABB_EN actually defined?
cd ~/dev/hi6250-src || exit 1

echo "=== tree-wide search (any file type) ==="
grep -rn "AP_ABB_EN" . 2>/dev/null | grep -v Binary | head -12

echo
echo "=== the clk_abb_192 registration context (1275-1330) ==="
sed -n '1275,1335p' drivers/clk/hisi/clk-kirin-common.c
