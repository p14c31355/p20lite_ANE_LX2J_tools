#!/bin/bash
# After the v99 catcher recovers the box: hunt the v100 crash trace in the
# durable log, then flash v101 (safe ud probe + 8 MiB heap) and verify.
set -u
cd ~/dev/p20-root
UV="/home/placeless/.hermes/bin/uv run --no-project --with pyusb python3"

echo "=== durable log read (crash hunt) ==="
timeout 300 $UV olog_main_read.py > /tmp/rd_crash.log 2>&1
echo "rc=$?"
cp -f /tmp/olog_main.txt logs/olog_after_v100crash.txt
grep -i "panic\|alloc\|oom" logs/olog_after_v100crash.txt | head -10
echo "=== v100 boot tail around the crash ==="
grep -n "em: ud_\|em: ex_fnv\|em: hs_cc0" logs/olog_after_v100crash.txt | tail -8

echo "=== now flash v101 ==="
bash flash_cycle.sh artifacts/fullerene-ane-v101-stock.img
sleep 120
timeout 300 $UV olog_main_read.py > /tmp/rd101.log 2>&1
echo "rc=$?"
cp -f /tmp/olog_main.txt logs/olog_v101_main.txt
grep -i "em: ud_\|em: blk_\|em: gpt_n\|em: ex_n\|panic" logs/olog_v101_main.txt | head -20
date
