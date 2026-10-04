#!/bin/bash
# The root-retry loop, v3.2.
#
# Fixes over v3.1 (both were observed live):
#   * the settled-boot test still rejected a good boot: after a wake the loop
#     starts with adb already present, so FRESH stays 0 and the `uptime < 1200`
#     bound applied - a boot that was up ~20 min was misread as "hung" while
#     adb was working fine.  Now a wake sets WOKE=1, which the settled test
#     accepts regardless of uptime (and the script's own first attempt skips
#     the reboot entirely when the phone is already reachable - rebooting a
#     working boot is the riskier path, before a failure the post-failure boots
#     hang).
#   * the post-root payload now also re-applies the USB default
#     (persist.sys.usb.config=mtp,adb + the file + the live switch): EMUI
#     re-writes the property to its stock value at some point (observed: after
#     the exploit-failure boots the property was back to
#     "hisuite,mtp,mass_storage,adb"), and every successful root is a chance
#     to restore it.  While it survives, boots bring adb up by themselves
#     (measured on the 10:23 and 12:46 boots).
set -u
cd "$(dirname "$0")"
LOG=usb_runs/pmsg_read32.log
say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }

EXP=/data/local/tmp/cve-2019-2215
FROZEN="$HOME/dev/p20-root/working/cve-2019-2215_0x134c838"
WANT_MD5=$(md5sum "$FROZEN" | cut -d' ' -f1)

adb_present() { timeout 8 adb devices 2>/dev/null | grep -qP '^\S+\tdevice$'; }
boot_done() { [ "$(timeout 10 adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; }

wait_for_adb() {
  local tries=$(( ${1} * 60 )) i
  for i in $(seq 1 "$tries"); do
    adb_present && return 0
    [ $((i % 10)) -eq 0 ] && say "  ...still no adb ($((i / 60)) min in)"
    sleep 60
  done
  return 1
}

try_noroot_read() {
  rm -f usb_runs/pmsg_noroot.bin
  timeout 90 adb pull /sys/fs/pstore/pmsg-ramoops-0 usb_runs/pmsg_noroot.bin >/dev/null 2>&1
  if [ -s usb_runs/pmsg_noroot.bin ] && grep -aq "ANEPv1->" usb_runs/pmsg_noroot.bin; then
    cp usb_runs/pmsg_noroot.bin usb_runs/pmsg.bin
    say "NO-ROOT READ SUCCEEDED: the pmsg record is in usb_runs/pmsg.bin"
    return 0
  fi
  say "  (noroot read unavailable: $([ -s usb_runs/pmsg_noroot.bin ] && echo 'readable but no marker' || echo 'not readable'))"
  return 1
}

attempt=0
WOKE=0
FIRST=1
while [ $attempt -lt 10 ]; do
  attempt=$((attempt+1))
  say "===== attempt $attempt ====="

  if [ $FIRST = 1 ] && adb_present; then
    say "phone is already reachable; using the current boot (no reboot)"
    WOKE=1
  fi
  FIRST=0

  if ! adb_present; then
    say "no adb: waiting up to 3 h for the phone (a physical press revives a hung boot)"
    if ! wait_for_adb 3; then
      say "adb did not return within 3 h - stopping; re-arm when the phone wakes"
      exit 1
    fi
    WOKE=1
    say "adb is back"
  fi

  if [ $WOKE = 0 ]; then
    say "rebooting for a clean heap"
    timeout 60 adb reboot 2>/dev/null
    sleep 40
    say "waiting for the new boot to settle (30 min)"
  else
    say "waiting for the boot to settle (30 min)"
  fi
  OK=0
  for i in $(seq 1 120); do
    if adb_present && boot_done; then
      up=$(timeout 10 adb shell cat /proc/uptime 2>/dev/null | awk '{print int($1)}')
      if [ $WOKE = 1 ] || [ -z "${up:-}" ] || [ "$up" -lt 1200 ]; then OK=1; break; fi
    fi
    sleep 15
  done
  if [ "$OK" != 1 ]; then
    say "no settled boot - the boot hung; waiting up to 3 h for a physical press"
    if ! wait_for_adb 3; then
      say "still nothing after 3 h - stopping; re-arm when the phone wakes"
      exit 1
    fi
    say "phone is awake; re-checking the boot directly"
    WOKE=1
    continue
  fi
  say "boot is settled (uptime $(timeout 10 adb shell cat /proc/uptime 2>/dev/null | awk '{print int($1)}')s); settling 300s more"
  sleep 300

  say "trying the no-root pstore read first"
  if try_noroot_read; then exit 0; fi

  GOT_MD5=$(timeout 30 adb shell "md5sum $EXP 2>/dev/null" | awk '{print $1}')
  if [ "$GOT_MD5" != "$WANT_MD5" ]; then
    timeout 60 adb push "$FROZEN" "$EXP" 2>&1 | tail -1
    timeout 10 adb shell "chmod 755 $EXP"
  fi

  say "starting the root shell (poll 25 min)"
  IN=/tmp/anepmsg32_in; OUT=usb_runs/pmsg_read32_att$attempt.out
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
    WOKE=0
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

  say "== re-applying the USB default (persist + file + live switch)"
  runroot 'setprop persist.sys.usb.config mtp,adb; echo setprop_rc=$?' | sed 's/^/    /'
  runroot 'echo -n mtp,adb > /data/property/persist.sys.usb.config; echo file_rc=$?' | sed 's/^/    /'

  exec 9>&-
  kill "$EXP_PID" 2>/dev/null
  say "SUCCESS on attempt $attempt"
  exit 0
done
say "all 10 attempts exhausted"
exit 1
