#!/bin/bash
# Two angles on the last gate:
#  a) the oeminfo partition's readable structure - is there an unlock flag in it?
#  b) the oeminfo_nvm service that liboeminfo talks to - what does IT read/write?
#  c) try flipping the property the toggle mirrors, with root, and see if the UI
#     ungrey s (the user can check instantly).
set -u
cd /home/placeless/dev/p20-root
P=firmware/partitions

echo "############ a) oeminfo strings mentioning lock/unlock"
strings -n 4 "$P/oeminfo.bin" | grep -iE "unlock|lock|flag|state" | sort -u | head -20
echo "--- and the JSON-ish keys:"
strings -n 6 "$P/oeminfo.bin" | grep -E '^\s*"' | sort -u | head -25

echo
echo "############ b) the oeminfo_nvm service"
timeout 60 adb shell 'ls -la /system/bin/*oeminfo* /vendor/bin/*oeminfo* /system/bin/hw/*oem* 2>/dev/null; echo ---; getprop init.svc.oeminfo_nvm' 2>&1 | head -10
timeout 60 adb shell 'for f in /system/bin/oeminfo_nvm /vendor/bin/oeminfo_nvm; do [ -f $f ] && { echo "== $f"; strings $f | grep -iE "unlock|lock|frp|flag|persist|misc|nvme|oeminfo|assert" | sort -u | head -25; }; done' 2>&1 | head -35

echo
echo "############ c) try the property, with root"
cat > /tmp/prop.sh <<'INNER'
id
echo "before: $(getprop sys.oem_unlock_allowed)"
setprop sys.oem_unlock_allowed 1
echo "after : $(getprop sys.oem_unlock_allowed)"
settings put global oem_unlock_allowed 1
echo "global: $(settings get global oem_unlock_allowed)"
echo "=== done ==="
exit
INNER
for attempt in 1 2 3 4 5; do
  OUT=$(timeout 240 adb shell /data/local/tmp/cve-2019-2215 < /tmp/prop.sh 2>&1 | tr -d '\000')
  echo "$OUT" | grep -aq "=== done ===" && { echo "$OUT" | grep -aE "before:|after :|global:|done"; break; }
  echo "  [attempt $attempt lost the race]"; sleep 15
done

echo
echo "############ verify from a plain shell"
timeout 30 adb shell 'getprop sys.oem_unlock_allowed; settings get global oem_unlock_allowed' 2>&1
