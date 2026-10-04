#!/bin/bash
# Read exactly what is stored in USRKEY, as hex, so we can compare it with the
# hash hisi-nve was supposed to have written.
set -u
cd /home/placeless/dev/p20-root

cat > /tmp/rd.sh <<'INNER'
id
echo "=== USRKEY hex ==="
/data/local/tmp/hisi-nve r USRKEY 2>/dev/null | od -A n -t x1 | tr -d ' \n'
echo
echo "=== frp 0x24 (from the partition) ==="
dd if=/dev/block/bootdevice/by-name/frp bs=4096 count=1 2>/dev/null | od -A n -t x1 -j 36 -N 4 | tr -d ' \n'
echo
echo "=== done ==="
exit
INNER

for attempt in 1 2 3 4 5 6; do
  OUT=$(timeout 240 adb shell /data/local/tmp/cve-2019-2215 < /tmp/rd.sh 2>&1 | tr -d '\000')
  if echo "$OUT" | grep -aq "=== done ==="; then
    echo "$OUT" | grep -aA1 "USRKEY hex" | tail -1 | sed 's/^/stored : /'
    echo "$OUT" | grep -aA1 "frp 0x24" | tail -1 | sed 's/^/frp0x24: /'
    break
  fi
  echo "  [attempt $attempt: no root shell]"
done

echo
echo "=== expected values for comparison ==="
python3 - <<'PY'
import hashlib
code = b"0123456789ABCDEF"
print("sha256(code) raw      :", hashlib.sha256(code).hexdigest())
print("sha256(code) lower hex:", hashlib.sha256(code).hexdigest())
print("sha256(sha256) raw    :", hashlib.sha256(hashlib.sha256(code).digest()).hexdigest())
print("code ascii            :", code.hex())
PY
