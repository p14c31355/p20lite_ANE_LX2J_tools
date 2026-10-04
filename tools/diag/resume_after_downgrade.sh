#!/bin/bash
# RESUME AFTER DOWNGRADE - run once adb can see the device again.
# Gate: the exploit is P20 Lite 4.4.23 specific. Do not push or run it unless
# /proc/version says 4.4.23. On 4.9.148 (EMUI 9) it would fail at best.
set -u

EXP=/home/placeless/dev/p20lite-cve/libs/arm64-v8a/cve-2019-2215
EXP_MD5=ffa2a9121ffa0e9ea8be4c5b8adff8df

echo "############ STEP 1 - is adb back?"
timeout 30 adb devices -l 2>&1 | head -4
if ! timeout 30 adb shell true >/dev/null 2>&1; then
  echo ">>> adb still cannot reach the device."
  echo "    On the phone: finish setup, then"
  echo "      設定 -> 端末情報 -> ビルド番号 を7回タップ"
  echo "      設定 -> 開発者向けオプション -> USBデバッグ ON"
  echo "      USB接続を「ファイル転送」にし、許可ダイアログで「許可」"
  exit 1
fi

echo
echo "############ STEP 2 - confirm the downgrade (THE GATE)"
K=$(timeout 30 adb shell 'cat /proc/version' 2>&1)
echo "kernel : $K"
timeout 30 adb shell 'getprop ro.build.display.id; getprop ro.build.version.release; getprop ro.build.version.sdk' 2>&1
case "$K" in
  *4.4.23*) echo ">>> PASS: kernel 4.4.23 - the exploit matches this kernel" ;;
  *) echo ">>> FAIL: not 4.4.23. Do NOT run the exploit. Stopping."; exit 2 ;;
esac

echo
echo "############ STEP 3 - device facts we need for the unlock step"
timeout 30 adb shell 'getprop ro.boot.flash.locked; getprop ro.boot.verifiedbootstate; getprop ro.boot.hardware; getprop ro.board.boardname; getprop ro.product.model; getprop persist.sys.usb.config' 2>&1
echo "--- SELinux ---"
timeout 30 adb shell 'getenforce' 2>&1
echo "--- uid ---"
timeout 30 adb shell 'id' 2>&1

echo
echo "############ STEP 4 - push the exploit and verify"
timeout 60 adb push "$EXP" /data/local/tmp/cve-2019-2215 2>&1 | tail -2
timeout 60 adb shell 'chmod 755 /data/local/tmp/cve-2019-2215' 2>&1
ONDEV=$(timeout 30 adb shell 'md5sum /data/local/tmp/cve-2019-2215 2>/dev/null || toybox md5sum /data/local/tmp/cve-2019-2215 2>/dev/null' 2>&1 | awk '{print $1}' | head -1)
echo "host md5: $EXP_MD5"
echo "dev  md5: $ONDEV"
if [ "$ONDEV" = "$EXP_MD5" ]; then
  echo ">>> PASS: exploit staged and identical"
else
  echo ">>> WARN: md5 mismatch (device may lack md5sum; compare sizes instead)"
  timeout 30 adb shell 'ls -la /data/local/tmp/cve-2019-2215' 2>&1
fi

echo
echo "############ STEP 5 - READ-ONLY recon before running anything"
echo "The exploit gives a root shell. First pass: read only, no writes."
timeout 30 adb shell 'ls -la /dev/socket/ 2>/dev/null | head -20' 2>&1
timeout 30 adb shell 'ls -la /dev/binder* 2>/dev/null' 2>&1

echo
echo "############ NEXT"
echo "Run the exploit and drive the root shell with a piped command list:"
echo '  timeout 600 adb shell "/data/local/tmp/cve-2019-2215" <<EOS'
echo '  id'
echo '  getenforce'
echo '  getprop ro.boot.flash.locked'
echo '  ls -la /proc/1/root/cust 2>/dev/null | head'
echo '  EOS'
echo
echo "Goal order: root -> READ oeminfo (FBLOCK flag) -> decide the write strategy."
echo "post_downgrade.sh has the detailed staging."
