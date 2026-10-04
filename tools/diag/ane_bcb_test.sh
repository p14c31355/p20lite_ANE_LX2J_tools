#!/bin/bash
# BCB tests: can the loader be steered into fastboot by the misc partition?
#
# Evidence this builds on (measured):
#   - backups/ANE-LX2J_20261002/misc.bin carries, at offset 0, the string
#     "bootonce-bootloader" - the standard Android "boot fastboot once" BCB
#     command. It is the only BCB command this device's misc has ever held.
#   - LK strings carry "boot-recovery" and misc handling errors
#     ("NO misc value, go to next mode!", "write misc cmd failed!"), so the
#     misc is read at boot.
#   - `adb reboot bootloader` does reach fastboot (used all day), which is the
#     Android/kernel side of the same mechanism.
#
# Tests (each harmless; all reversible):
#   T1 read the current misc BCB (is the bootonce still there?)
#   T2 write "bootonce-bootloader" -> reboot -> does fastboot appear?
#   T3 if T2 worked: fastboot reboot -> is the marker gone (once semantics)?
#   T4 in fastboot: `fastboot reboot-bootloader` - does the loader itself
#      support returning to fastboot? This is the vendor-side feature that a
#      button-free cycle ultimately wants.
#
# Root exists only inside the exploit's stdin session, so the misc work happens
# there; everything else is ordinary adb/fastboot.
set -u
cd "$(dirname "$0")"

if ! timeout 15 adb devices 2>/dev/null | grep -qP "^\S+\tdevice$"; then
  echo "device is not on adb"; exit 1
fi

echo "== ensure the exploit is present"
if ! timeout 10 adb shell 'ls /data/local/tmp/cve-2019-2215' 2>/dev/null | grep -q cve; then
  timeout 60 adb push "$HOME/dev/p20lite-cve/exploit/cve-2019-2215" /data/local/tmp/ 2>&1 | tail -1
fi
timeout 10 adb shell 'chmod 755 /data/local/tmp/cve-2019-2215'

cat > /tmp/anebcb2.sh <<'INNER'
echo "=== root check ==="
id
D=$(ls /dev/block/*/by-name/misc /dev/block/platform/*/by-name/misc 2>/dev/null | head -1)
echo "misc device=$D"
[ -z "$D" ] && { echo "=== no-misc ==="; exit; }
echo "=== T1: current BCB (first 64 bytes) ==="
dd if="$D" bs=64 count=1 2>/dev/null | strings | head -3
echo "=== backup ==="
dd if="$D" of=/data/local/tmp/misc.bak bs=4096 2>/dev/null
chmod 644 /data/local/tmp/misc.bak
echo "=== write bootonce-bootloader + NUL padding (32-byte command field) ==="
printf 'bootonce-bootloader\0\0\0\0\0\0\0\0\0\0\0\0' > /data/local/tmp/bcb.bin
dd if=/data/local/tmp/bcb.bin of="$D" bs=32 count=1 conv=notrunc 2>/dev/null
sync
echo "=== read back ==="
dd if="$D" bs=64 count=1 2>/dev/null | strings | head -3
echo "=== bcb-written ==="
exit
INNER

OK=0
for attempt in 1 2; do
  OUT=$(timeout 240 adb shell /data/local/tmp/cve-2019-2215 < /tmp/anebcb2.sh 2>&1 | tr -d '\000')
  if echo "$OUT" | grep -q "=== bcb-written ==="; then
    echo "$OUT" | sed -n '/=== root check ===/,$p'
    OK=1; break
  fi
  echo "  [attempt $attempt: no root shell]"
  sleep 5
done
if [ "$OK" != 1 ]; then
  echo "== root not obtained; nothing was written."
  exit 1
fi

timeout 120 adb pull /data/local/tmp/misc.bak "backups/misc_$(date +%Y%m%d_%H%M%S).bak" 2>&1 | tail -1

echo
echo "== T2: reboot; does 'bootonce-bootloader' bring up fastboot?"
timeout 30 adb reboot >/dev/null 2>&1
FB1=""
for i in $(seq 1 40); do
  timeout 6 fastboot devices 2>/dev/null | grep -q . && { FB1=yes; break; }
  sleep 5
done
if [ -z "$FB1" ]; then
  echo "== T2 verdict: no fastboot (the loader ignored the BCB)."
  exit 2
fi
echo "   T2 verdict: fastboot came up from the BCB"

echo
echo "== T4: does the loader itself support 'fastboot reboot-bootloader'?"
timeout 30 fastboot reboot-bootloader 2>&1 | head -2
FB2=""
for i in $(seq 1 30); do
  timeout 6 fastboot devices 2>/dev/null | grep -q . && { FB2=yes; break; }
  timeout 6 adb devices 2>/dev/null | grep -qP "^\S+\tdevice$" && break
  sleep 4
done
if [ -n "$FB2" ]; then
  echo "   T4 verdict: YES - the loader returns to fastboot on its own."
else
  echo "   T4 verdict: no (reboot-bootloader not supported / reverted)."
fi
