#!/bin/bash
# Wait for the TL00 8.0.0.151 package to finish downloading, then check whether its
# kernel is the one the device runs.
#
# The decisive test is the kernel's embedded version string: the build date+time is
# unique per build, and the device reports "Fri Mar 1 00:11:18 CST 2019".
set -u
cd /home/placeless/dev/p20-root
F="firmware/azrom/ANE-TL00_Anne-TL00_8.0.0.151(C01)_all_cn_Firmware_Android_8.0_EMUI_8.0_05015FYE.rar"

echo "############ waiting for the download to complete"
for i in $(seq 1 90); do
  if [ -f "$F" ]; then
    SZ=$(stat -c%s "$F")
    echo "  present: $SZ bytes"
    # a complete package is > 3 GB; also make sure it stopped growing
    sleep 5
    SZ2=$(stat -c%s "$F")
    [ "$SZ" = "$SZ2" ] && [ "$SZ" -gt 3000000000 ] && break
  fi
  sleep 20
done
ls -la "$F" || { echo "!!! never finished"; exit 1; }

echo
echo "############ extract and check the kernel"
bash check_kernel_candidates.sh "$F" 2>&1 | tail -30
