#!/bin/bash
# Wait for all four downloads to land, then check each kernel in turn.
#
# What we need from each kernel: the version string (does it read "Fri Mar 1
# 00:11:18 CST 2019" like the device?) and the difference
#     avc_cache - fair_sched_class
# because the exploit only ever uses the two constants as a difference:
#     kaslr_offset   = read(task+0x88) - FAIR_SCHED_CLASS
#     avc_cache_addr = kaslr_offset + AVC_CACHE
# so a candidate is usable iff its difference matches the running kernel's.
set -u
cd /home/placeless/dev/p20-root
D=firmware/azrom

echo "############ waiting for the remaining downloads"
for i in $(seq 1 120); do
  N=$(ls "$D"/*.rar "$D"/*.zip 2>/dev/null | wc -l)
  P=$(ls "$D"/*.part 2>/dev/null | wc -l)
  echo "  complete=$N in-progress=$P"
  [ "$N" -ge 4 ] && [ "$P" -eq 0 ] && break
  sleep 30
done

echo
echo "############ checking each kernel (this unpacks and reconstructs each one)"
FILES=$(ls "$D"/*.rar "$D"/*.zip 2>/dev/null)
# TL00 and the first C719 were already checked or are being checked right now;
# checking twice is cheap compared to getting this wrong.
bash check_kernel_candidates.sh $FILES 2>&1 | tee /tmp/all_candidates.log

echo
echo "############ summary"
grep -E "^== |Linux version|avc_cache - fair_sched_class" /tmp/all_candidates.log
echo
echo "### device target:"
echo "###   Linux version ... Fri Mar 1 00:11:18 CST 2019"
echo "### (8.0.0.110(C635), Apr 2018 : difference 0x132e838)"
echo "### (TL00 8.0.0.151(C01), Jun 2018 : difference 0x134a838)"
echo "### (exploit's built-in constants   : difference 0x135c838)"
