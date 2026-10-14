#!/bin/bash
# Night runner: autonomous ANE-LX2J experimentation until 22:00 device time.
#
# Design (all from today's measurements, see docs/ANE_BOOT_CONTRACT.md):
#
#  * A HANG-type payload makes the loader's watchdog fall back to fastboot
#    after ~4.5 min (L1 timeline 09:38:06 -> fastboot 09:42:46, caught live).
#    An SMC-reset-loop payload instead falls back to the rescue screen, which
#    needs a human key press. => The queue holds hang-type images only, and
#    the loop pin-pongs through fastboot with no Android needed at all:
#      fastboot -> flash probe -> boot -> probe runs and hangs ->
#      fastboot again -> next probe -> ...
#  * When the queue is empty (or says RESTORE / USBJOB), the stock kernel goes
#    back on and the phone lands in Android for the user.
#  * Android on this device drops adb a few seconds after boot (USB mode
#    manager). adb is only visible in a short early window - the runner polls
#    for it and uses it if the queue still has work.
#  * While a probe is alive the webcam watches the screen (RCH colour reads).
#
# The queue is night_queue.txt: one entry per line, top line = next.
#   artifacts/<name>.img -> flash that probe
#   RESTORE              -> restore the stock now, wait for Android
#   USBJOB               -> stock boot, then best-effort persist.sys.usb.config
#                           = mtp,adb (needs one exploit run inside the adb
#                           window; max 3 lifetime attempts, then gives up)
#
# One actor only: nothing else should drive fastboot/adb while this runs.
set -u
cd "$(dirname "$0")"

END_HOUR=${END_HOUR:-22}
# Absolute stop time in epoch seconds. The default is the next 06:00 device
# time, so an overnight launch runs the verification loop until the morning
# and then winds the phone down into Android; a bare END_HOUR (same-day) is
# accepted as a shim for short sessions.
if [ -z "${END_EPOCH:-}" ]; then
  now_epoch=$(date +%s)
  today_six=$(date -d "today 06:00" +%s)
  if [ "$now_epoch" -lt "$today_six" ]; then
    END_EPOCH=$today_six
  else
    END_EPOCH=$(date -d "tomorrow 06:00" +%s)
  fi
fi
STOCK=firmware/kernel_stock.bin
MISC_HOLD=firmware/misc_bootloader.img
MISC_CLEAR=firmware/misc_clear.img
QUEUE=night_queue.txt
TS=$(date +%Y%m%d_%H%M)
LOG="usb_runs/night_${TS}.log"
JLOG="usb_runs/night_journal_${TS}.log"
CAMD="usb_runs/cam_${TS}"
mkdir -p usb_runs "$CAMD"
[ -f "$QUEUE" ] || : > "$QUEUE"

say() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }
adb_ok() { timeout 10 adb devices 2>/dev/null | grep -qP '^\S+\tdevice$'; }
fb_ok()  { timeout 8 fastboot devices 2>/dev/null | grep -q .; }

iface_count() { lsusb -v -d 12d1:107e 2>/dev/null | grep -cE "bInterfaceNumber"; }

classify() {
  if lsusb | grep -q "18d1:d00d"; then echo "fastboot"; return; fi
  if lsusb | grep -q "12d1:107e"; then echo "gadget$(iface_count)if"; return; fi
  echo dark
}

journal_sweep() {
  timeout 8 journalctl -k --no-pager --since "30 seconds ago" 2>/dev/null \
    | grep -E "usb 1-1:" >> "$JLOG" || true
}

watch_screen() {
  # webcam readout while a probe is alive (RCH colours are saturated fills)
  ( local d="$CAMD"
    for i in $(seq 1 9); do
      sleep 18
      timeout 20 ffmpeg -y -hide_banner -loglevel error -f v4l2 -input_format mjpeg \
        -i /dev/video0 -frames:v 1 "$d/$(date +%H%M%S)_$i.jpg" 2>/dev/null || true
      timeout 60 python3 ane_cam_read.py --frames 3 >> "$d/read.log" 2>&1 || true
    done ) &
}

fire_probe() {
  local art="$1"
  say "PROBE: flashing $art"
  # Clear the BCB first: with "bootloader" left in misc by the last restore,
  # the reboot below would park in fastboot instead of running the probe.
  # (restore_stock() sets it back; this is the other half of the toggle.)
  timeout 60 fastboot flash misc "$MISC_CLEAR" 2>&1 | tail -1 | tee -a "$LOG"
  out=$(timeout 300 fastboot flash kernel "$art" 2>&1); echo "$out" | tail -2 | tee -a "$LOG"
  echo "$out" | grep -q "OKAY" || { say "PROBE: flash did not report OKAY"; return 1; }
  timeout 60 fastboot reboot 2>&1 | head -1 | tee -a "$LOG"
  say "PROBE: $art fired; hang expected, fastboot fallback in ~4.5 min"
  echo "$(date +%H:%M:%S) $art" >> usb_runs/night_probe_runs.txt
  watch_screen
  return 0
}

restore_stock() {
  say "RESTORE: flashing the stock kernel"
  out=$(timeout 300 fastboot flash kernel "$STOCK" 2>&1); echo "$out" | tail -2 | tee -a "$LOG"
  echo "$out" | grep -q "OKAY" || { say "RESTORE: flash did not report OKAY"; return 1; }
  # Skip EMUI: park the phone back in fastboot instead of letting it boot
  # Android. The BCB command at the start of misc is what the loader reads to
  # decide its boot target (the unlock flow used "bootonce-bootloader" the
  # same way); "bootloader" keeps landing in fastboot. Android only comes back
  # through release_to_android() at the wind-down.
  timeout 60 fastboot flash misc "$MISC_HOLD" 2>&1 | tail -2 | tee -a "$LOG"
  timeout 60 fastboot reboot 2>&1 | head -1 | tee -a "$LOG"
  say "RESTORE: stock rebooted (BCB=bootloader: EMUI skipped)"
  return 0
}

release_to_android() {
  say "RELEASE: clearing the BCB and restoring the stock kernel"
  out=$(timeout 300 fastboot flash kernel "$STOCK" 2>&1); echo "$out" | tail -2 | tee -a "$LOG"
  timeout 60 fastboot flash misc "$MISC_CLEAR" 2>&1 | tail -1 | tee -a "$LOG"
  timeout 60 fastboot reboot 2>&1 | head -1 | tee -a "$LOG"
  say "RELEASE: stock rebooted (BCB cleared: Android boots)"
  return 0
}

wait_android() {  # $1 = seconds budget
  local t0; t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt "${1:-300}" ]; do
    adb_ok && return 0
    sleep 5
  done
  return 1
}

usb_job() {
  [ -f .usb_default_done ] && return 0
  local att; att=$(cat .usb_default_attempts 2>/dev/null || echo 0)
  [ "$att" -ge 3 ] && { say "USBJOB: attempts exhausted"; return 0; }
  echo $((att + 1)) > .usb_default_attempts
  say "USBJOB: attempt $((att + 1)) (short window; best effort)"
  timeout 150 bash ane_set_usb_default.sh >> "$LOG" 2>&1 || true
  if [ "$(timeout 10 adb shell getprop persist.sys.usb.config 2>/dev/null | tr -d '\r')" = "mtp,adb" ]; then
    touch .usb_default_done
    say "USBJOB: persist.sys.usb.config is now mtp,adb"
  else
    say "USBJOB: not set (window too short or no root this boot)"
  fi
}

handle_special() {  # $1 = RESTORE | USBJOB ; returns after doing the work
  case "$1" in
    RESTORE)
      fb_ok && restore_stock
      # EMUI is skipped now: the BCB parks the device back in fastboot, so no
      # android window is expected - do not burn minutes waiting for one.
      sleep 10; say "RESTORE: stock back, phone parked in fastboot"
      ;;
    USBJOB)
      if ! adb_ok; then
        fb_ok && restore_stock
        wait_android 15 || say "USBJOB: no android window (EMUI skipped)"
      fi
      adb_ok && usb_job
      ;;
  esac
}

LAST_STATE=""
LAST_FIRE=0
say "night runner start; stop at $(date -d "@$END_EPOCH" '+%m-%d %H:%M'); queue: $(wc -l < "$QUEUE") entries"
say "logs: $LOG  journal: $JLOG  camera: $CAMD"

while :; do
  if [ "$(date +%s)" -ge "$END_EPOCH" ]; then say "END: stop time reached"; break; fi

  journal_sweep

  ST=$(classify)
  if [ "$ST" != "$LAST_STATE" ]; then say "state: ${LAST_STATE:-start} -> $ST"; LAST_STATE="$ST"; fi

  if [ "$ST" = "fastboot" ]; then
    if [ -s "$QUEUE" ]; then
      ENTRY=$(head -1 "$QUEUE")
      NOW=$(date +%s)
      if [ $((NOW - LAST_FIRE)) -lt 90 ]; then sleep 5; continue; fi
      case "$ENTRY" in
        artifacts/*)
          if [ -f "$ENTRY" ]; then
            if fire_probe "$ENTRY"; then sed -i '1d' "$QUEUE"; LAST_FIRE=$NOW; fi
          else
            say "queue: missing $ENTRY (dropping)"; sed -i '1d' "$QUEUE"
          fi ;;
        RESTORE|USBJOB)
          sed -i '1d' "$QUEUE"; LAST_FIRE=$(date +%s)
          handle_special "$ENTRY" ;;
        "")
          sed -i '1d' "$QUEUE" ;;
        *)
          say "queue: refusing non-artifact entry '$ENTRY' (dropping)"; sed -i '1d' "$QUEUE" ;;
      esac
    else
      restore_stock && sleep 10 && say "queue empty: stock back, fastboot-parked (EMUI skipped)"
      if [ "${STOP_WHEN_QUEUE_EMPTY:-0}" = 1 ]; then
        say "queue is empty and the stock is back - exiting (STOP_WHEN_QUEUE_EMPTY)"
        break
      fi
    fi
    continue
  fi

  if [ "$ST" != "dark" ]; then
    if adb_ok; then
      timeout 30 bash ane_screen_on.sh >/dev/null 2>&1 || true
      if [ -s "$QUEUE" ]; then
        ENTRY=$(head -1 "$QUEUE")
        case "$ENTRY" in
          artifacts/*)
            say "ADB: window open -> reboot to bootloader for the next probe"
            timeout 25 adb reboot bootloader 2>&1 | head -1 | tee -a "$LOG" || true
            sleep 6 ;;
          RESTORE)
            say "ADB: already in Android for a RESTORE entry"
            sed -i '1d' "$QUEUE"; LAST_FIRE=$(date +%s) ;;
          USBJOB)
            sed -i '1d' "$QUEUE"; LAST_FIRE=$(date +%s); usb_job ;;
        esac
      else
        # opportunistic USB job when there is nothing else queued
        usb_job
        if [ "${STOP_WHEN_QUEUE_EMPTY:-0}" = 1 ]; then
          say "queue is empty and the phone is in Android - exiting (STOP_WHEN_QUEUE_EMPTY)"
          break
        fi
        sleep 60
      fi
    fi
  fi

  sleep 4
done

# wind-down: release the phone from fastboot into Android for the user
say "wind-down: settling the phone into Android"
for i in $(seq 1 90); do
  if [ "$(classify)" = "fastboot" ]; then release_to_android; sleep 10; continue; fi
  if adb_ok; then say "wind-down: android is up - done"; break; fi
  sleep 20
done
say "night runner exiting (device: $(classify), queue left: $(wc -l < "$QUEUE"))"
