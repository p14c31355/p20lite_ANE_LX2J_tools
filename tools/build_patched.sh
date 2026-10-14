#!/bin/bash
# Apply both source fixes idempotently, build, and report.
set -u
cd /home/placeless/dev/p20lite-cve
NDK=$(ls -d ~/Android/Sdk/ndk/*/ 2>/dev/null | head -1)

echo "=== fix the sources (idempotent) ==="
python3 /home/placeless/dev/p20-root/fix_sources.py
echo "fix exit: $?"

echo
echo "=== build ==="
"${NDK}ndk-build" -j4 NDK_PROJECT_PATH=. APP_BUILD_SCRIPT=./Android.mk \
    APP_PLATFORM=android-28 APP_ABI=arm64-v8a > /tmp/build3.log 2>&1
rc=$?
echo "build exit: $rc"
echo "errors: $(grep -c 'error:' /tmp/build3.log)"
grep -m3 'error:' /tmp/build3.log

echo
ls -la libs/arm64-v8a/cve-2019-2215 2>/dev/null || echo "(no binary)"
md5sum libs/arm64-v8a/cve-2019-2215 2>/dev/null
