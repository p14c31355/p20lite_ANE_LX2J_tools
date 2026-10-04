#!/bin/bash
# Verify the RCH probe's DSS register offsets against the vendor headers:
#   DSS_BASE           0xE8600000
#   RCH_VG0_DMA_OFFSET 0x20000 -> 0xE8620000, DATA_ADDR0 = +0x60
#   RCH_VG1_DMA_OFFSET 0x28000 -> 0xE8628000
#   RCH_G0_DMA_OFFSET  0x38000 -> 0xE8638000
#   RCH_G1_DMA_OFFSET  0x40000 -> 0xE8640000
cd ~/dev/hi6250-src || exit 1
echo "=== RCH *_DMA_OFFSET defines ==="
grep -rn "RCH_VG0_DMA_OFFSET\|RCH_VG1_DMA_OFFSET\|RCH_G0_DMA_OFFSET\|RCH_G1_DMA_OFFSET" --include=*.h drivers/hisi/ap/platform/hi6250/ 2>/dev/null | head -8
echo
echo "=== DATA_ADDR0 in the RCH/DMA block (offset 0x60?) ==="
grep -rn "DATA_ADDR0\|DMA_DATA_ADDR" --include=*.h drivers/hisi/ap/platform/hi6250/ 2>/dev/null | head -10
echo
echo "=== DSS base ==="
grep -rn "define DSS_BASE\|DSS_BASE " --include=*.h drivers/hisi/ap/platform/hi6250/ 2>/dev/null | head -5
