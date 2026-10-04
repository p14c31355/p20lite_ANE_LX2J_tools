#!/bin/bash
# Extract the KERNEL block from the official 8.0.0.110(C635) UPDATE.APP and turn
# it into an ELF with symbols, so we can read the true addresses of the two
# constants the exploit hardcodes (FAIR_SCHED_CLASS, AVC_CACHE).
#
# Both kernels come from the same Huawei source tree for the same device, and
# the linker layout is deterministic for a given config, so the addresses from
# 8.0.0.110 are the best available proxy for the running 8.0.0.151.
set -u
W=/tmp/kern
mkdir -p "$W"

echo "############ 1. locate UPDATE.APP and list its blocks"
APP=/tmp/fw3/Software/dload/UPDATE.APP
if [ ! -f "$APP" ]; then
  echo "  not extracted yet - pulling it out of the zip"
  python3 - <<'PY'
import zipfile, os
z=zipfile.ZipFile('/tmp/fw3/Software/dload/update_sd.zip')
print("zip entries:", z.namelist()[:10])
PY
fi
ls -la "$APP" 2>/dev/null || echo "  (need to extract UPDATE.APP first)"

echo
echo "############ 2. list the blocks (looking for KERNEL)"
cd /home/placeless/dev/p20-root
python3 list_update_app2.py 2>/dev/null | head -40 || echo "(list script missing)"
