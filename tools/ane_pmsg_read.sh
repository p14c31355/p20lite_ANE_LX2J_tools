#!/bin/bash
# After the [key-probe, pmsg-dump, RESTORE] fires: wait for Android, take root
# (one run per boot, never kill a progressing run - the SELinux policy stage
# took ~16 minutes on the run that worked), then read the pstore files out.
#
# What we expect in /sys/fs/pstore/pmsg-ramoops-0: a 128-byte record the
# pmsg-dump probe appended - "ANEPv1->" + the key probe's raw 24-entry trace +
# the step-mark block.  That is the whole point: the probe's data rides out
# through Android's own ramoops/pstore reader, which is the only channel this
# kernel leaves open (no /dev/mem, no /proc/kcore).
set -u
cd "$(dirname "$0")"
LOG=usb_runs/pmsg_read.log
say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }

EXP=/data/local/tmp/cve-2019-2215
FROZEN="$HOME/dev/p20-root/working/cve-2019-2215_0x134c838"
WANT_MD5=$(md5sum "$FROZEN" | cut -d' ' -f1)

say "waiting for adb (the RESTORE fire should bring Android)"
for i in $(seq 1 180); do
  timeout 8 adb devices 2>/dev/null | grep -qP '^\S+\tdevice$' && break
  sleep 5
done
if ! timeout 8 adb devices 2>/dev/null | grep -qP '^\S+\tdevice$'; then
  say "no adb device appeared"; exit 1
fi
say "adb present; waiting for boot_completed"
for i in $(seq 1 60); do
  bc=$(timeout 10 adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
  [ "$bc" = "1" ] && break
  sleep 10
done
say "boot_completed=$bc; settling 75s"
sleep 75

say "ensuring the frozen exploit (md5 $WANT_MD5)"
GOT_MD5=$(timeout 30 adb shell "md5sum $EXP 2>/dev/null" | awk '{print $1}')
if [ "$GOT_MD5" != "$WANT_MD5" ]; then
  timeout 60 adb push "$FROZEN" "$EXP" 2>&1 | tail -1
  timeout 10 adb shell "chmod 755 $EXP"
  GOT_MD5=$(timeout 30 adb shell "md5sum $EXP" | awk '{print $1}')
fi
[ "$GOT_MD5" = "$WANT_MD5" ] || { say "FATAL: wrong binary ($GOT_MD5)"; exit 1; }
say "md5 ok"

say "starting the root shell (patience: up to 30 min, no early kill)"
IN=/tmp/anepmsg_in; OUT=usb_runs/pmsg_read_run.out
rm -f "$IN"; : > "$OUT"; mkfifo "$IN"
adb shell "$EXP" < "$IN" >> "$OUT" 2>&1 &
EXP_PID=$!
exec 9> "$IN"
ROOT=0
for i in $(seq 1 1800); do
  grep -q "uid=0(root)" "$OUT" 2>/dev/null && { say "ROOT after ${i}s"; ROOT=1; break; }
  sleep 1
done
if [ "$ROOT" != 1 ]; then
  say "no root within 30 min; tail:"
  tail -4 "$OUT" | sed 's/^/    /'
  exec 9>&-
  kill "$EXP_PID" 2>/dev/null
  exit 1
fi

runroot() {
  local mark="MK$RANDOM$RANDOM" before
  before=$(wc -c < "$OUT")
  printf 'echo %s\n%s\necho %s\n' "$mark" "$1" "$mark" >&9
  for i in $(seq 1 180); do
    sleep 1
    [ "$(tail -c +$((before+1)) "$OUT" | grep -c "^$mark$")" -ge 2 ] && break
  done
  tail -c +$((before+1)) "$OUT" | awk -v m="$mark" 'BEGIN{n=0} {if ($0==m){n++; next} if (n==1) print}'
}

say "== root id:"
runroot 'id' | sed 's/^/    /'
say "== reading the pstore files into /data/local/tmp"
runroot 'cat /sys/fs/pstore/pmsg-ramoops-0 > /data/local/tmp/pmsg.bin; echo pmsg_rc=$?; cat /sys/fs/pstore/console-ramoops-0 > /data/local/tmp/console.bin; echo console_rc=$?; ls -la /data/local/tmp/pmsg.bin /data/local/tmp/console.bin' | sed 's/^/    /'
say "== pulling"
for f in pmsg console; do
  timeout 120 adb pull /data/local/tmp/$f.bin usb_runs/$f.bin 2>&1 | tail -1
done
ls -la usb_runs/pmsg.bin usb_runs/console.bin 2>/dev/null

exec 9>&-
kill "$EXP_PID" 2>/dev/null
say "done"
