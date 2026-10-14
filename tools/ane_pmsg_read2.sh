#!/bin/bash
# Read the pmsg record out: root via the frozen exploit, then pull the pstore
# files.  Upgraded from the first try two ways, both measured differences from
# the runs that won:
#   * settle 300s, not 75s - the run that worked started at ~340s uptime
#   * poll for root for 60 minutes, not 30 - the policy stage is minutes-scale
#     and on the run that won it took ~16; letting one die early wastes a boot
#   * on failure: reboot and retry (up to 3 attempts) - a failed run makes the
#     current boot useless for a second run, and a fresh boot is the lever that
#     mattered on every win so far
# The pmsg record itself survives reboots; nothing here can lose it.
set -u
cd "$(dirname "$0")"
LOG=usb_runs/pmsg_read2.log
say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }

EXP=/data/local/tmp/cve-2019-2215
FROZEN="$HOME/dev/p20-root/working/cve-2019-2215_0x134c838"
WANT_MD5=$(md5sum "$FROZEN" | cut -d' ' -f1)

adb_present() { timeout 8 adb devices 2>/dev/null | grep -qP '^\S+\tdevice$'; }

attempt=0
while [ $attempt -lt 3 ]; do
  attempt=$((attempt+1))
  say "===== attempt $attempt ====="

  if ! adb_present; then
    say "waiting up to 15 min for adb"
    for i in $(seq 1 60); do adb_present && break; sleep 15; done
    adb_present || { say "no adb"; exit 1; }
  fi

  say "rebooting for a clean heap"
  timeout 60 adb reboot 2>/dev/null
  sleep 40
  say "waiting for a settled boot"
  OK=0
  for i in $(seq 1 60); do
    if adb_present; then
      bc=$(timeout 10 adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
      up=$(timeout 10 adb shell cat /proc/uptime 2>/dev/null | awk '{print int($1)}')
      if [ "$bc" = "1" ] && [ -n "${up:-}" ] && [ "$up" -lt 900 ]; then OK=1; break; fi
    fi
    sleep 15
  done
  [ "$OK" = 1 ] || { say "no settled boot this attempt"; continue; }
  say "settled at $(timeout 10 adb shell cat /proc/uptime 2>/dev/null | awk '{print int($1)}')s uptime; settling 300s (the winning run started at ~340s)"
  sleep 300

  say "ensuring the frozen exploit"
  GOT_MD5=$(timeout 30 adb shell "md5sum $EXP 2>/dev/null" | awk '{print $1}')
  if [ "$GOT_MD5" != "$WANT_MD5" ]; then
    timeout 60 adb push "$FROZEN" "$EXP" 2>&1 | tail -1
    timeout 10 adb shell "chmod 755 $EXP"
    GOT_MD5=$(timeout 30 adb shell "md5sum $EXP" | awk '{print $1}')
  fi
  [ "$GOT_MD5" = "$WANT_MD5" ] || { say "FATAL: wrong binary"; exit 1; }

  say "starting the root shell (patience: 60 min, no early kill)"
  IN=/tmp/anepmsg2_in; OUT=usb_runs/pmsg_read2_att$attempt.out
  rm -f "$IN"; : > "$OUT"; mkfifo "$IN"
  adb shell "$EXP" < "$IN" >> "$OUT" 2>&1 &
  EXP_PID=$!
  exec 9> "$IN"
  ROOT=0
  for i in $(seq 1 3600); do
    grep -q "uid=0(root)" "$OUT" 2>/dev/null && { say "ROOT after ${i}s"; ROOT=1; break; }
    if ! kill -0 "$EXP_PID" 2>/dev/null; then say "exploit client exited early"; break; fi
    sleep 1
  done
  if [ "$ROOT" != 1 ]; then
    say "attempt $attempt: no root; tail:"
    tail -3 "$OUT" | sed 's/^/    /'
    exec 9>&-
    kill "$EXP_PID" 2>/dev/null
    sleep 5
    continue
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

  say "== id:"
  runroot 'id' | sed 's/^/    /'
  say "== reading pstore into /data/local/tmp"
  runroot 'cat /sys/fs/pstore/pmsg-ramoops-0 > /data/local/tmp/pmsg.bin; echo pmsg_rc=$?; cat /sys/fs/pstore/console-ramoops-0 > /data/local/tmp/console.bin; echo console_rc=$?; ls -la /data/local/tmp/pmsg.bin /data/local/tmp/console.bin' | sed 's/^/    /'
  say "== pulling"
  for f in pmsg console; do
    timeout 120 adb pull /data/local/tmp/$f.bin usb_runs/$f.bin 2>&1 | tail -1
  done
  ls -la usb_runs/pmsg.bin usb_runs/console.bin 2>/dev/null

  exec 9>&-
  kill "$EXP_PID" 2>/dev/null
  say "SUCCESS on attempt $attempt"
  exit 0
done
say "all attempts failed"
exit 1
