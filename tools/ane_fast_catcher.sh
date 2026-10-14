#!/usr/bin/env bash
# Catch the loader's brief fastboot window and fire the next probe inside it.
#
# The problem this fixes (user-reported): after a probe dies, the LK escalates
# to the EMUI recovery (12d1:107e, one interface) - but on the way there it
# opens a fastboot window (18d1:d00d) for a short moment (measured worst case
# ~1.6s).  The runner's poll loop (sleep 4 + classify) only lands inside that
# window sometimes; every miss parks the phone in the recovery and needs a
# physical button press.  Polling cannot be made reliably fast enough.
#
# So react to the EVENT, not to the clock: follow the kernel log and the
# instant the fastboot device enumerates, flash the queue head and reboot.
# Two fastboot writes are ~0.4s total, which fits inside the window where the
# polled path only sometimes did.  The runner stays as the slow fallback, so
# a miss here still gets caught there; a double-fire (both actors on the same
# window) just flashes the same probe twice, which is harmless.
#
# The queue pop happens here too, guarded by a lock and a re-read, so a
# double-fire cannot skip a probe: the second actor's pop sees a different
# head and leaves the queue alone.
set -u
cd "$(dirname "$0")"
LOG=usb_runs/fast_catcher.log
mkdir -p usb_runs

say() { echo "$(date '+%m-%d %H:%M:%S') $*" | tee -a "$LOG"; }

say "armed: following the kernel log; firing into any fastboot window"

timeout 23400 journalctl -k -f -n 0 --no-pager 2>/dev/null | while read -r line; do
  case "$line" in
    *"idVendor=18d1, idProduct=d00d"*)
      ENTRY=$(head -1 night_queue.txt 2>/dev/null)
      [ -n "$ENTRY" ] || ENTRY=firmware/kernel_stock.bin
      say "fastboot window seen; head is: $ENTRY"
      case "$ENTRY" in
        artifacts/*)
          timeout 20 fastboot flash misc firmware/misc_clear.img >/dev/null 2>&1
          out=$(timeout 40 fastboot flash kernel "$ENTRY" 2>&1)
          if echo "$out" | grep -q "OKAY"; then
            timeout 20 fastboot reboot >/dev/null 2>&1
            say "fired $ENTRY ($(echo "$out" | grep -oE 'OKAY \[[^]]*\]' | tail -1))"
            # Pop, but only if the head is still the entry we fired - the
            # runner may have popped it already.
            if mkdir .queue.lock 2>/dev/null; then
              now=$(head -1 night_queue.txt 2>/dev/null)
              [ "$now" = "$ENTRY" ] && sed -i '1d' night_queue.txt
              rmdir .queue.lock 2>/dev/null
            fi
          else
            say "window lost before the flash finished: $(echo "$out" | tail -1)"
          fi
          ;;
        RESTORE|firmware/*)
          timeout 20 fastboot flash misc firmware/misc_clear.img >/dev/null 2>&1
          out=$(timeout 40 fastboot flash kernel firmware/kernel_stock.bin 2>&1)
          if echo "$out" | grep -q "OKAY"; then
            timeout 20 fastboot reboot >/dev/null 2>&1
            say "restored stock kernel ($(echo "$out" | grep -oE 'OKAY \[[^]]*\]' | tail -1)) - phone heads for Android"
            if mkdir .queue.lock 2>/dev/null; then
              now=$(head -1 night_queue.txt 2>/dev/null)
              [ "$now" = "$ENTRY" ] && sed -i '1d' night_queue.txt
              rmdir .queue.lock 2>/dev/null
            fi
          else
            say "restore window lost: $(echo "$out" | tail -1)"
          fi
          ;;
        *)
          say "head is not a probe ($ENTRY); leaving it to the runner"
          ;;
      esac
      ;;
  esac
done
