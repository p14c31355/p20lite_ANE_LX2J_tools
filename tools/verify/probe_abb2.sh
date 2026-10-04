#!/bin/bash
# Find the exact abb gate constants: ABB_SCBAKDATA, AP_ABB_EN, LPM3_ABB_EN.
cd ~/dev/hi6250-src || exit 1

echo "=== ABB_SCBAKDATA definition ==="
grep -rn "ABB_SCBAKDATA" --include=*.h --include=*.c drivers/ include/ 2>/dev/null | head -8

echo
echo "=== AP_ABB_EN / LPM3_ABB_EN (all headers) ==="
grep -rn "AP_ABB_EN\|LPM3_ABB_EN" --include=*.h drivers/ include/ arch/ 2>/dev/null | head -10

echo
echo "=== who registers clk_abb_192 (DT prop name) ==="
grep -rn "clk_abb_192\|abb_192" --include=*.c drivers/clk/hisi/clk-kirin-common.c | head -8
