#!/bin/bash
# Flash an artifact hands-free, wait out the boot's storage phase, then
# read the durable log. Usage: bash cycle_read.sh <artifact.img> <tag>
# (supersedes the per-version run_vNN.sh wrappers)
set -u
ART="${1:?usage: cycle_read.sh <artifact.img> <tag>}"
TAG="${2:?usage: cycle_read.sh <artifact.img> <tag>}"
cd ~/dev/p20-root
bash flash_cycle.sh "$ART"
sleep 120
timeout 300 /home/placeless/.hermes/bin/uv run --no-project --with pyusb python3 olog_main_read.py > "/tmp/rd_${TAG}.log" 2>&1
echo "read rc=$?"
cp -f /tmp/olog_main.txt "logs/olog_${TAG}_main.txt"
echo "--- ${TAG} ---"
grep -i "em: c17_\|em: c18_\|em: c8_ok" /tmp/olog_main.txt | head -8
date
