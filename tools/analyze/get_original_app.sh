#!/bin/bash
# Check whether our rebuilt update_sd.zip really carries the whole UPDATE.APP,
# and if not, get the original one out of the RAR.
set -u
cd /home/placeless/dev/p20-root

echo "############ 1. what does zipfile think the member size is?"
python3 - <<'PY'
import zipfile
for p in ("firmware/samesize/update_sd.zip",
          "firmware/custfix/update_sd.zip",
          "firmware/eocd/update_sd.zip"):
    try:
        with zipfile.ZipFile(p) as z:
            i = z.getinfo("UPDATE.APP")
            print(f"{p}: usize={i.file_size:,} csize={i.compress_size:,} method={i.compress_type}")
    except Exception as e:
        print(f"{p}: {e}")
PY

echo
echo "############ 2. extract the original update_sd.zip from the RAR"
mkdir -p /tmp/orig
if [ ! -f /tmp/orig/update_sd.zip ]; then
  /home/placeless/opt/7zz/7zz e -y -o/tmp/orig "firmware/ANE-LX2J_8.0.0.110_C635.rar" \
      "Software/dload/update_sd.zip" 2>&1 | tail -4
fi
ls -la /tmp/orig/ 2>/dev/null

echo
echo "############ 3. and its member size"
python3 - <<'PY'
import zipfile, os
p = "/tmp/orig/update_sd.zip"
if os.path.exists(p):
    with zipfile.ZipFile(p) as z:
        i = z.getinfo("UPDATE.APP")
        print(f"original: usize={i.file_size:,} csize={i.compress_size:,} method={i.compress_type}")
PY
