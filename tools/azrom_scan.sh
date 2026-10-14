#!/bin/bash
# Which P20 Lite (ANE) firmware products does azrom actually list?
echo "=== products for LX2J / L22J / L12J / L02J (our board) ==="
grep -iE "lx2j|l22j|l12j|l02j" /tmp/azrom_urls.txt | sort -u
echo
echo "=== products whose URL contains 151 (any model) ==="
grep -E "151" /tmp/azrom_urls.txt | sort -u | head -30
echo
echo "=== products for the ANE board, 8.0.0 era, LX2 family ==="
grep -iE "ane-(lx2|l22|l12)" /tmp/azrom_urls.txt | sort -u | head -40
echo
echo "counts: LX2J/L22J=$(grep -icE 'lx2j|l22j' /tmp/azrom_urls.txt)  LX2-any=$(grep -icE 'ane-lx2' /tmp/azrom_urls.txt)"
