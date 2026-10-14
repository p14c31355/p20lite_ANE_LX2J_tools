#!/bin/bash
# Does the vendor display driver drive normal scanout from DATA_ADDR0 only,
# or can DATA_ADDR1/2 hold the scanned buffer?
cd ~/dev/hi6250-src || exit 1
echo "=== who writes DATA_ADDR0/1/2 ==="
grep -rln "DATA_ADDR0\|DATA_ADDR1\|DATA_ADDR2" --include=*.c drivers/ 2>/dev/null | head -10
echo
F=$(grep -rln "DATA_ADDR0" --include=*.c drivers/video 2>/dev/null | head -1)
echo "video file: $F"
[ -n "$F" ] && grep -n "DATA_ADDR0\|DATA_ADDR1\|DATA_ADDR2" "$F" | head -20
