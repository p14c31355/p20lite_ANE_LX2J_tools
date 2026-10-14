#!/bin/bash
# ONE clean-boot session: reboot, start a persistent root shell, then
#   (a) back up the nvme partition, (b) read the FBLOCK flags.
# Nothing is written. The FBLOCK write is a separate, deliberate step.
set -u

EXP=/data/local/tmp/cve-2019-2215
NVME_TOOL=/data/local/tmp/hisi-nve
WORK=/data/local/tmp/p20
IN=/tmp/root.in
OUT=/tmp/root.out

echo "############ 1. push the nvme tool (no root needed)"
timeout 60 adb push /home/placeless/dev/hisi-nve/libs/arm64-v8a/hisi-nve "$NVME_TOOL" 2>&1 | tail -1
timeout 30 adb shell "chmod 755 $NVME_TOOL" 2>&1

echo
echo "############ 2. reboot for a clean heap"
timeout 60 adb reboot 2>&1
sleep 25
for i in $(seq 1 40); do
  [ "$(timeout 20 adb get-state 2>/dev/null | head -1)" = "device" ] && break
  sleep 10
done
for i in $(seq 1 40); do
  [ "$(timeout 20 adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ] && break
  sleep 10
done
echo "  booted; settling..."
sleep 75

echo
echo "############ 3. start the persistent root shell (FIFO kept open)"
rm -f "$IN" "$OUT"; mkfifo "$IN"; : > "$OUT"
adb shell "$EXP" < "$IN" >> "$OUT" 2>&1 &
EXP_PID=$!
exec 9> "$IN"
for i in $(seq 1 90); do
  grep -q "uid=0(root)" "$OUT" 2>/dev/null && { echo "  ROOT after ${i}s"; break; }
  sleep 1
done
if ! grep -q "uid=0(root)" "$OUT" 2>/dev/null; then
  echo ">>> exploit did not reach root this boot. tail:"; tail -8 "$OUT"; exit 1
fi

# helper: run a command in the root shell, print its output
runroot() {
  local mark="MK$RANDOM$RANDOM" before
  before=$(wc -c < "$OUT")
  printf 'echo %s\n%s\necho %s\n' "$mark" "$1" "$mark" > "$IN"
  for i in $(seq 1 90); do
    sleep 1
    [ "$(tail -c +$((before+1)) "$OUT" | grep -c "^$mark$")" -ge 2 ] && break
  done
  tail -c +$((before+1)) "$OUT" | awk -v m="$mark" 'BEGIN{n=0} {if ($0==m){n++; next} if (n==1) print}'
}

echo
echo "############ 4. who are we now (uid and SELinux domain)"
runroot 'id; cat /proc/self/attr/current; getenforce'

echo
echo "############ 5. BACKUP nvme (before anything else)"
runroot "mkdir -p $WORK; dd if=/dev/block/bootdevice/by-name/nvme of=$WORK/nvme.backup.img; echo dd_exit=\$?; ls -la $WORK/; md5sum $WORK/nvme.backup.img"

echo
echo "############ 6. read the FBLOCK flags (read-only)"
runroot "$NVME_TOOL r FBLOCK"

echo
echo "############ 7. also dump the first bytes of nvme for the record"
runroot "dd if=/dev/block/bootdevice/by-name/nvme bs=128 count=1 2>/dev/null | od -c | head -8"

echo
echo "############ session is still open. To write later:"
echo "  echo '$NVME_TOOL w FBLOCK 0' > $IN"
echo "### leaving the shell up; kill this script to end it"
while kill -0 "$EXP_PID" 2>/dev/null; do sleep 5; done
echo "### exploit exited; session over"
exec 9>&-
