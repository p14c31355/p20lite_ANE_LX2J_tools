#!/bin/bash
# Why does the bootloader reject our unlock code?
#
# The FRP gate used to be checked first, so the code check was never reached.
# Now that OEM unlocking is enabled, the code check runs - and it fails.
#
# hisi-nve hashes the value before writing USRKEY on hi6250 (nve_hashed_key = 1),
# so what sits in the partition should be SHA256("0123456789ABCDEF"). Read what is
# actually there and compare against the plausible encodings.
set -u
cd /home/placeless/dev/p20-root
CODE=0123456789ABCDEF

cat > /tmp/usrkey.sh <<'INNER'
id
echo "=== USRKEY now ==="
/data/local/tmp/hisi-nve r USRKEY
echo "=== done ==="
exit
INNER

for attempt in 1 2 3 4 5 6; do
  OUT=$(timeout 240 adb shell /data/local/tmp/cve-2019-2215 < /tmp/usrkey.sh 2>&1 | tr -d '\000')
  echo "$OUT" | grep -aq "=== done ===" && { echo "$OUT" | grep -aE "USRKEY|Read|done" | head -6; break; }
  echo "  [attempt $attempt: no root shell]"
done

echo
echo "############ what it SHOULD be, in each plausible encoding"
python3 - "$CODE" <<'PY'
import hashlib, sys
code = sys.argv[1].encode()
d_raw = hashlib.sha256(code).digest()
d_hex = hashlib.sha256(code).hexdigest().encode()
print(f"code               : {code.decode()}")
print(f"sha256 raw (32 B)  : {d_raw.hex()}")
print(f"sha256 hex (64 B)  : {d_hex.decode()}")
print()
for name, v in (("code as ascii", code), ("code upper", code.upper()),
                ("sha256 raw", d_raw), ("sha256 hex", d_hex)):
    print(f"{name:18} : {v[:32].hex() if isinstance(v, bytes) else v}")
PY
