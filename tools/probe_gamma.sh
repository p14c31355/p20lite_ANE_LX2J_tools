#!/bin/bash
# oeminfo_gamma is the service that liboeminfo talks to - it owns the locker state.
# Its strings will name the keys it reads and writes.
set -u
cd /home/placeless/dev/p20-root
timeout 120 adb pull /vendor/bin/oeminfo_gamma firmware/oeminfo_gamma 2>&1 | tail -1
ls -la firmware/oeminfo_gamma
echo
echo "=== lock / nv key strings ==="
strings -n 3 firmware/oeminfo_gamma | grep -iE "unlock|lock|frp|flag|fblock|usrkey|adblock|bootctl|nvme|oeminfo|persist|misc|nv |nve|assert|state" | sort -u | head -40
echo
echo "=== all short uppercase-ish tokens (likely NV key names) ==="
strings -n 4 firmware/oeminfo_gamma | grep -E "^[A-Z][A-Z0-9_]{3,15}$" | sort -u | head -40
