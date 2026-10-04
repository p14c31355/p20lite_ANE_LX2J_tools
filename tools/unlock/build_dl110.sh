#!/bin/bash
# Re-extract the firmware tree the samesize builder reads from, then build.
#
# The builder takes the ORIGINAL packages from /tmp/fw3/Software/dload/ - both the
# outer update_sd.zip and the inner ANE-L22J_hw_jp one. /tmp was wiped since the
# last successful build, so restore them from the RAR first.
set -u
cd /home/placeless/dev/p20-root
RAR=firmware/ANE-LX2J_8.0.0.110_C635.rar
OUT=/tmp/fw3

need_extract=0
[ -f "$OUT/Software/dload/update_sd.zip" ] || need_extract=1
[ -f "$OUT/Software/dload/ANE-L22J_hw_jp/update_sd_ANE-L22J_hw_jp.zip" ] || need_extract=1

if [ "$need_extract" = 1 ]; then
  echo "############ extracting Software/dload/ from the RAR (about 2.6 GB)"
  mkdir -p "$OUT"
  /home/placeless/opt/7zz/7zz x -y -o"$OUT" "$RAR" "Software/dload/*" 2>&1 | tail -6
else
  echo "############ firmware tree already present"
fi
echo
find "$OUT" -maxdepth 4 -name "*.zip" -printf "%s\t%p\n" 2>/dev/null | head -5
echo
echo "############ build"
/tmp/zv/bin/python build_samesize4.py 2>&1 | tail -35
echo
echo "############ result"
ls -la firmware/dl110/ 2>/dev/null
