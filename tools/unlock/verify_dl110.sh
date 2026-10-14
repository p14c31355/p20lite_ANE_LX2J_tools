#!/bin/bash
# Verify the dl110 build against the originals, and show the version list the
# updater will actually read.
set -u
cd /home/placeless/dev/p20-root

echo "############ point the verifier at dl110"
python3 - <<'PY'
s = open('/home/placeless/dev/p20-root/verify_samesize_both.py').read()
s = s.replace('firmware/custfix/', 'firmware/dl110/')
open('/home/placeless/dev/p20-root/verify_dl110.py', 'w').write(s)
print("wrote verify_dl110.py")
PY

echo
echo "############ run it"
python3 verify_dl110.py 2>&1 | tail -25

echo
echo "############ the version list as the updater sees it"
python3 - <<'PY'
import zipfile
for p in ("firmware/dl110/update_sd.zip",
          "firmware/dl110/update_sd_ANE-L22J_hw_jp.zip"):
    try:
        with zipfile.ZipFile(p) as z:
            data = z.read("SOFTWARE_VER_LIST.mbn")
        print(f"{p}:")
        print(f"  {len(data)} bytes")
        for line in data.splitlines():
            print("   ", line.decode("ascii", "replace"))
    except Exception as e:
        print(f"{p}: {e}")
PY

echo
echo "############ sizes against the originals"
for f in update_sd.zip update_sd_ANE-L22J_hw_jp.zip; do
  o=/tmp/fw3/Software/dload/$f
  [ "$f" = "update_sd_ANE-L22J_hw_jp.zip" ] && o=/tmp/fw3/Software/dload/ANE-L22J_hw_jp/$f
  n=firmware/dl110/$f
  if [ -f "$o" ] && [ -f "$n" ]; then
    echo "$f: original $(stat -c%s "$o")   build $(stat -c%s "$n")"
  fi
done
