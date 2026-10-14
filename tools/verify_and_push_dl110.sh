#!/bin/bash
# Verify the dl110 build, then stage it on the phone's SD card.
set -u
cd /home/placeless/dev/p20-root

echo "############ 1. verify against the originals"
python3 verify_dl110.py 2>&1 | tail -22

echo
echo "############ 2. the version list the updater will read"
python3 - <<'PY'
import zipfile
for p in ("firmware/dl110/update_sd.zip",
          "firmware/dl110/update_sd_ANE-L22J_hw_jp.zip"):
    with zipfile.ZipFile(p) as z:
        data = z.read("SOFTWARE_VER_LIST.mbn")
    print(f"{p}: {len(data)} bytes")
    for line in data.splitlines():
        print("   ", line.decode("ascii", "replace"))
PY

echo
echo "############ 3. stage on the SD card (over adb)"
timeout 60 adb shell 'ls -la /storage/D4DD-4FB0/dload/ 2>&1 | head -8'
echo "--- clearing the old build ---"
timeout 60 adb shell 'rm -f /storage/D4DD-4FB0/dload/update_sd.zip /storage/D4DD-4FB0/dload/update_sd_ANE-L22J_hw_jp.zip; ls /storage/D4DD-4FB0/dload/'
echo "--- pushing the dl110 build ---"
timeout 900 adb push firmware/dl110/update_sd.zip /storage/D4DD-4FB0/dload/update_sd.zip 2>&1 | tail -1
timeout 900 adb push firmware/dl110/update_sd_ANE-L22J_hw_jp.zip /storage/D4DD-4FB0/dload/update_sd_ANE-L22J_hw_jp.zip 2>&1 | tail -1
echo "--- syncing and verifying on the device ---"
timeout 120 adb shell 'sync; ls -la /storage/D4DD-4FB0/dload/*.zip'
echo "--- md5 on device ---"
timeout 300 adb shell 'md5sum /storage/D4DD-4FB0/dload/update_sd.zip /storage/D4DD-4FB0/dload/update_sd_ANE-L22J_hw_jp.zip' 2>&1
echo "--- md5 on host ---"
md5sum firmware/dl110/update_sd.zip firmware/dl110/update_sd_ANE-L22J_hw_jp.zip
