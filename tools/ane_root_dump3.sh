#!/bin/bash
# Root + RAM dump, clean-boot recipe with retries.
#
# The 2026-10-02 winning recipe: reboot for a clean heap, wait for a settled
# boot, settle 75s more, then ONE exploit run (later runs on the same boot die
# silently).  A failed run also makes the NEXT boot slow (~7-10 min to a
# reachable adb, measured), so the waits here are generous.  Up to 3 attempts.
#
# Payload once rooted: dump 0x34000000..0x34900000 (9 MiB, covers bbox-mem and
# pstore-mem - the probe trace slot and step marks), pull it, then set
# persist.sys.usb.config = mtp,adb so adb survives future boots.
set -u
cd "$(dirname "$0")"
LOG=usb_runs/root_dump3.log
say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }

EXP=/data/local/tmp/cve-2019-2215
FROZEN="$HOME/dev/p20-root/working/cve-2019-2215_0x134c838"
WANT_MD5=$(md5sum "$FROZEN" | cut -d' ' -f1)

adb_present() { timeout 8 adb devices 2>/dev/null | grep -qP '^\S+\tdevice$'; }
adb_ready_settled() {
  adb_present || return 1
  local bc up
  bc=$(timeout 10 adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
  up=$(timeout 10 adb shell cat /proc/uptime 2>/dev/null | awk '{print int($1)}')
  [ "$bc" = "1" ] && [ -n "${up:-}" ] && [ "$up" -lt 900 ]
}

attempt=0
while [ $attempt -lt 3 ]; do
  attempt=$((attempt+1))
  say "===== attempt $attempt ====="

  if ! adb_present; then
    say "no adb right now; waiting up to 15 min for the phone"
    for i in $(seq 1 60); do adb_present && break; sleep 15; done
    if ! adb_present; then
      say "adb did not come back - the phone may need its USB mode picked by hand"
      exit 1
    fi
  fi

  say "rebooting for a clean heap (the winning recipe)"
  timeout 60 adb reboot 2>/dev/null
  sleep 40

  say "waiting for a reachable, settled boot (up to 15 min; a post-failure boot is slow)"
  OK=0
  for i in $(seq 1 60); do
    if adb_ready_settled; then OK=1; break; fi
    sleep 15
  done
  if [ "$OK" != 1 ]; then
    say "no settled boot this attempt"
    continue
  fi
  say "boot reachable and settled: $(timeout 10 adb shell cat /proc/uptime 2>/dev/null | awk '{print int($1)}')s uptime"
  say "settle 75s"
  sleep 75

  say "ensuring the frozen exploit (md5 $WANT_MD5)"
  GOT_MD5=$(timeout 30 adb shell "md5sum $EXP 2>/dev/null" | awk '{print $1}')
  if [ "$GOT_MD5" != "$WANT_MD5" ]; then
    timeout 60 adb push "$FROZEN" "$EXP" 2>&1 | tail -1
    timeout 10 adb shell "chmod 755 $EXP"
    GOT_MD5=$(timeout 30 adb shell "md5sum $EXP" | awk '{print $1}')
  fi
  if [ "$GOT_MD5" != "$WANT_MD5" ]; then
    say "FATAL: wrong binary on the device ($GOT_MD5)"; exit 1
  fi
  say "md5 ok"

  say "starting the root shell (fifo kept open)"
  IN=/tmp/anedmp3_in; OUT=usb_runs/root_dump3_att$attempt.out
  rm -f "$IN"; : > "$OUT"
  mkfifo "$IN"
  adb shell "$EXP" < "$IN" >> "$OUT" 2>&1 &
  EXP_PID=$!
  exec 9> "$IN"
  ROOT=0
  for i in $(seq 1 900); do
    grep -q "uid=0(root)" "$OUT" 2>/dev/null && { say "ROOT after ${i}s"; ROOT=1; break; }
    sleep 1
  done
  if [ "$ROOT" != 1 ]; then
    say "attempt $attempt: no root. tail:"
    tail -4 "$OUT" | sed 's/^/    /'
    exec 9>&-
    kill "$EXP_PID" 2>/dev/null
    sleep 5
    continue
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
  runroot 'id' | sed 's/^/    /'
  say "== dumping reserved RAM 0x34000000..0x34900000 (9 MiB)"
  runroot 'dd if=/dev/mem of=/data/local/tmp/ram_34.bin bs=4096 skip=212992 count=2304 2>/tmp/dd.err; echo dd_rc=$?; cat /tmp/dd.err; ls -la /data/local/tmp/ram_34.bin' | sed 's/^/    /'
  say "== pulling the dump"
  timeout 300 adb pull /data/local/tmp/ram_34.bin usb_runs/ram_34.bin 2>&1 | tail -1
  ls -la usb_runs/ram_34.bin 2>/dev/null || say "no dump landed"

  say "== making mtp,adb the persistent USB mode"
  runroot 'setprop persist.sys.usb.config mtp,adb; echo setprop_rc=$?' | sed 's/^/    /'
  runroot 'echo -n mtp,adb > /data/property/persist.sys.usb.config; echo file_rc=$?' | sed 's/^/    /'
  runroot 'getprop persist.sys.usb.config; cat /data/property/persist.sys.usb.config; echo' | sed 's/^/    /'

  exec 9>&-
  kill "$EXP_PID" 2>/dev/null
  say "SUCCESS on attempt $attempt"
  exit 0
done
say "all attempts failed"
exit 1
