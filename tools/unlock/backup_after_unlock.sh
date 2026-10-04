#!/bin/bash
# Post-unlock backup: dump the nvme partition in its clean unlocked state and add it
# to the backup set, along with a record of the bootloader's verdict.
#
# The device was wiped by the unlock, so the exploit has to be pushed again. The
# frozen build (working/cve-2019-2215_0x134c838) is the one that defeated SELinux,
# since SELinux is back to enforcing after the reboot.
set -u
cd /home/placeless/dev/p20-root
B=backups/ANE-LX2J_20261002
EXPL=working/cve-2019-2215_0x134c838

echo "############ 0. record the bootloader's verdict"
{
  date
  echo "ro.boot.flash.locked      = $(timeout 20 adb shell getprop ro.boot.flash.locked | tr -d '\r')"
  echo "ro.boot.verifiedbootstate = $(timeout 20 adb shell getprop ro.boot.verifiedbootstate | tr -d '\r')"
  echo "ro.boot.veritymode        = $(timeout 20 adb shell getprop ro.boot.veritymode | tr -d '\r')"
  echo "device                    = $(timeout 20 adb shell getprop ro.build.display.id | tr -d '\r')"
  echo "kernel                    = $(timeout 20 adb shell cat /proc/version | tr -d '\r')"
} | tee "$B/unlock_verification.txt"

echo
echo "############ 1. push the exploit and get root"
timeout 90 adb push "$EXPL" /data/local/tmp/cve-2019-2215 2>&1 | tail -1
timeout 30 adb shell 'chmod 755 /data/local/tmp/cve-2019-2215'

cat > /tmp/dumpk.sh <<'INNER'
id
dd if=/dev/block/bootdevice/by-name/nvme of=/data/local/tmp/nvme_unlocked.bin bs=4096 2>&1 | tail -1
chmod 666 /data/local/tmp/nvme_unlocked.bin
ls -la /data/local/tmp/nvme_unlocked.bin
echo "=== done ==="
exit
INNER

GOT=0
for attempt in 1 2 3 4 5 6 7 8; do
  OUT=$(timeout 240 adb shell /data/local/tmp/cve-2019-2215 < /tmp/dumpk.sh 2>&1 | tr -d '\000')
  if echo "$OUT" | grep -aq "=== done ==="; then
    echo "$OUT" | grep -aE "records|nvme_unlocked|uid=0" | head -4
    GOT=1
    break
  fi
  echo "  [attempt $attempt: no root shell yet]"
done

if [ "$GOT" = "1" ]; then
  echo
  echo "############ 2. pull it into the backup set"
  timeout 120 adb pull /data/local/tmp/nvme_unlocked.bin "$B/nvme_unlocked_after_setup.bin" 2>&1 | tail -1
  cd "$B"
  cp -f nvme_unlocked_after_setup.bin nvme_CURRENT_unlocked.bin 2>/dev/null || true
  find . -maxdepth 1 -type f ! -name MD5SUMS.txt -printf '%f\n' | sort | xargs md5sum > MD5SUMS.txt
  echo "--- verify:"
  md5sum -c MD5SUMS.txt 2>&1 | tail -14
  echo
  echo "--- FBLOCK and USRKEY in the fresh dump:"
  cd /home/placeless/dev/p20-root
  python3 - <<'PY'
import hashlib
d = open("backups/ANE-LX2J_20261002/nvme_unlocked_after_setup.bin","rb").read()
print(f"size: {len(d):,}")
i = 0
while True:
    j = d.find(b"FBLOCK", i)
    if j == -1: break
    print(f"  FBLOCK @0x{j:06x} = {d[j+8]:02x}")
    i = j + 1
want = hashlib.sha256(b"0123456789ABCDEF").digest()
i = 0
n = 0
while True:
    j = d.find(b"USRKEY", i)
    if j == -1: break
    n += 1
    ok = d[j+20:j+20+32] == want
    print(f"  USRKEY @0x{j:06x} = {'our key (SHA256 of the code)' if ok else d[j+20:j+20+16].hex() + '...'}")
    i = j + 1
print(f"  USRKEY copies: {n}")
PY
else
  echo "  could not get root this round - the backup set is unchanged"
fi
