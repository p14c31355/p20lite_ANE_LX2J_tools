#!/bin/bash
# Tidy up: keep the TL00 kernel artefacts we measured, drop its huge unpack tree,
# and leave the automated all-candidates check as the single running job.
set -u
cd /home/placeless/dev/p20-root
D="/tmp/cand/ANE-TL00_Anne-TL00_8.0.0.151(C01)_all_cn_Firmware_Android_8.0_EMUI_8.0_05015FYE"
mkdir -p kernels/tl00
cp "$D/inner/kern/kernel.elf" kernels/tl00/kernel.elf 2>/dev/null
cp "$D/inner/kern/kernel.img" kernels/tl00/kernel.img 2>/dev/null
ls -la kernels/tl00/
echo "kept: $(du -sh kernels/ | cut -f1) total in kernels/"
rm -rf "$D"
echo "freed the TL00 unpack tree"
df -h /home | tail -1
