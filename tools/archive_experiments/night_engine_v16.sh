#!/bin/bash
# Night engine v7: the unmanned loop over ADB + fastboot.
#
# Per fresh boot (journal event):
#   1. ADB: CNXN -> the piggybacked ring tail in the reply (v155+), else the
#      OPEN(shell:log) fallback -> rings_night/
#   2. reset: fastboot `oem crash`, falling back to the ADB `shell:crash`
#   3. loader window -> flash the queued image -> reboot -> next boot
#
# Rules this encodes (learned the hard way):
#  - sysfs/lsusb *product cache* can lag; the ADB attempt is therefore made
#    on every fresh enumeration (the conversation either answers or it does
#    not - a gate on the cached product merely loses windows).
#  - The loader's fastboot presence is checked with `lsusb -v` (a fresh
#    descriptor fetch), never the cached sysfs string.
#  - Only the host journal's "usb 1-1: new ..." events are trustworthy boot
#    detectors.
#  - One EP1 conversation per window; the CNXN is sent twice (one-transfer
#    lag), and the ADB work must be the FIRST thing after a fresh enum.
#
# Usage: night_engine.sh <image> [cycles]
set -u
cd ~/dev/p20-root || exit 1
IMG="${1:?usage: night_engine.sh <image> [cycles]}"
CYCLES="${2:-99999}"
UV=/home/placeless/.hermes/bin/uv
LOG="logs/night_$(date +%m%d_%H%M%S).log"
mkdir -p logs rings_night
log() { echo "[$(date +%m%d\ %H:%M:%S)] $*" >>"$LOG"; }

lk_up() {
  lsusb -v -d 18d1:d00d 2>/dev/null | grep -qi "iProduct.*Fastboot2.0"
}
last_event() {
  # v15: trigger on the ATTACH line itself ("new high-speed USB device
  # number N" - every attach prints one, each is unique). The old
  # product-string trigger went STALE on product-less attaches (the
  # kernel's strings never printed) and returned the previous attach's
  # line, so whole boots were skipped in silence (dev 49, 17:20).
  journalctl -k --no-pager -n 600 2>/dev/null \
    | grep "usb 1-1: new high-speed USB device number" | tail -1
}

flash_now() {
  log "LK window; flashing $IMG"
  timeout 180 fastboot -s "$S" flash kernel "$IMG" >>"$LOG" 2>&1
  timeout 20 fastboot -s "$S" reboot >>"$LOG" 2>&1
  STALL=0  # v11: restart the stall clock with every flash; the v193 rescue
           # misfired once (1007 15:27) by counting stall time across a live
           # replacement boot and crashing it.
  log "flashed + rebooted"
}

S=SCV7N18927000473
log "=== night engine v16 start img=$IMG cycles=$CYCLES ==="
EV="$(last_event)"
STALL=0
for c in $(seq 1 "$CYCLES"); do
  if lk_up; then
    flash_now
    sleep 5
    EV="$(last_event)"
    continue
  fi

  CUR="$(last_event)"
  if [ "$CUR" != "$EV" ]; then
    EV="$CUR"
    STALL=0
    log "c$c: usb event: $CUR"
    # v12: host-side descriptor forensics for every boot (works for
    # garbled boots too - no USB session needed).
    bash forensics_snap.sh >>"$LOG" 2>&1
    # v15: CUR is the attach line; classify via the product line.
    # v16: SCOPE the product search to THIS attach's device number - the
    # unscoped tail-1 grabbed the PREVIOUS attach's product line and
    # mislabelled product-less kernel attaches as "loader" (dev 53).
    DEVNO="$(printf '%s' "$CUR" | sed -n 's/.*device number \([0-9]*\).*/\1/p')"
    last_p="$(journalctl -k -n 300 --no-pager 2>/dev/null | grep -A8 "usb 1-1: new high-speed USB device number ${DEVNO} " | grep "usb 1-1: Product: " | head -1)"
    case "$last_p" in
      *"Product: Fastboot2.0"*)
        log "c$c: loader attach; next"
        sleep 2
        continue
        ;;
    esac
    # v188: garbled-product boots ("Љ") have broken descriptors - pyusb
    # cannot even find EP1 (Invalid endpoint address 0x81), so every
    # session attempt is dead weight. v15: a product-less attach (kernel
    # strings never printed) is the same class - skip.
    if [ -z "$last_p" ]; then
      log "c$c: product-less attach; skip (no sessions possible)"
      continue
    fi
    if printf '%s' "$last_p" | grep -q "Љ"; then
      log "c$c: garbled product; skip sessions"
      continue
    fi
    if ! printf '%s' "$last_p" | grep -q "ANE fastboot"; then
      log "c$c: unexpected product; skip"
      continue
    fi
        #
        # v178: the boot tends to die on its own at ~+20-25 s (no interaction
        # involved), and the ADB path's replies have never once reached the
        # host, while the fastboot-class `oem xfer` header DID arrive once
        # (the OKAY of the very first auto-snapshot). So claim the window as
        # early as allowed with the proven class FIRST: a raw ring pull via
        # `oem xfer r` (the whole durable ring, the documented most-valuable
        # read). The old ~12 s settle was tuned for bulk grabs whose writes
        # fired at ~+16 s - too late against a +20 s death.
        # v187: wait for the post-bringup window. Sessions fired at +6-40 s
        # land while the storage bring-up starves the USB service: the
        # SET_CONFIGURATION dance times out (Errno 110) and the xfer writes
        # EIO. With the SP805 wall broken, boots now live 30+ min, so the
        # first touch can afford to wait ~3 min for a settled responder and
        # an unprejudiced EP1 (failed early sessions poison it otherwise).
        # v12: settle ~120 s real (bad boots die at ~4 m 45 s; v11's
        # unbounded journalctl loop stretched 180 s to ~280 s and missed
        # the window). Cheap bounded journal tail checks, early abort the
        # moment the loader's "Fastboot2.0" takes over.
        for _s in $(seq 1 25); do
          last_p="$(journalctl -k -n 40 --no-pager 2>/dev/null | grep "usb 1-1: Product: " | tail -1)"
          case "$last_p" in
            *"Fastboot2.0"*) break ;;
          esac
          sleep 3
        done
        if lk_up; then
          log "c$c: settle aborted; loader up"
          flash_now
          sleep 5
          continue
        fi
        mkdir -p rings_night
        # v192: ADB CNXN FIRST - the long-established law on this box is
        # that the responder reliably services only the FIRST conversation
        # per window. The c318 (2544-byte reply, good) and c51 (400-byte
        # stale-only cut) both ran the CNXN AFTER two xfer burns; the
        # original v155-era order was CNXN-first, and it belongs first
        # again. The small CNXN exchange (~10 s) gets the fresh EP1; the
        # heavy 32 KiB xfer tries afterwards on whatever is left.
        CNXN_OK=0
        for a in 1 2 3; do
          rm -f /tmp/adb_raw_last.bin
          if timeout 60 "$UV" run --with pyusb --no-project python3 adb_cycle.py log "rings_night/adb_${c}.bin" >>"$LOG" 2>&1; then
            log "c$c: ring $(stat -c %s "rings_night/adb_${c}.bin" 2>/dev/null) bytes (attempt $a)"
            CNXN_OK=1
            break
          fi
          # Forensics: keep each attempt's raw wire bytes (the last-file would
          # otherwise be overwritten by the later LK attempts).
          cp /tmp/adb_raw_last.bin "rings_night/raw_c${c}_a${a}.bin" 2>/dev/null || true
          log "c$c: adb attempt $a failed"
          # If the kernel already died (the loader took over), stop burning
          # attempts against the loader's fastboot - it just answers
          # "FAILCommand not allowed." and wastes the window.
          last_p="$(journalctl -k --no-pager 2>/dev/null | grep "usb 1-1: Product: " | tail -1)"
          case "$last_p" in
            *"Fastboot2.0"*) log "c$c: kernel gone after attempt $a"; break ;;
          esac
          sleep 5
        done
        # v183: two ring-xfer attempts per boot. The +6 s write often lands
        # in the mid-bringup EIO phase (fast fail, cheap), while the boot
        # now lives minutes - a second attempt ~30 s later catches the
        # endpoint once the bringup has settled. 90 s per attempt both fits
        # a working 32 KiB stream (the FIFO-drain pace is ~486 B/s) and
        # caps a dead-endpoint drag.
        # v13: ring-xfer only as a fallback. When the CNXN collection just
        # succeeded, the kernel's magic reset lands within ~2-50 s and the
        # xfers only time out against the loader (~3 min per cycle wasted).
        if [ "$CNXN_OK" = "1" ]; then
          log "c$c: skip ring xfer (cnxn collection ok)"
        else
          rm -f "rings_night/ring_c${c}.bin"
          if timeout 60 "$UV" run --with pyusb --no-project python3 fb_xfer.py r 348d0000 8000 "rings_night/ring_c${c}.bin" >>"$LOG" 2>&1; then
            log "c$c: ring xfer $(stat -c %s "rings_night/ring_c${c}.bin" 2>/dev/null) bytes"
          else
            log "c$c: ring xfer failed"
          fi
        fi
        python3 boot_ledger.py >>"$LOG" 2>&1 || true
        mkdir -p snaps
        # Snapshot only while the kernel is still on USB. Against the loader
        # it is a guaranteed multi-minute waste (the phone sits untouched on
        # the fastboot screen while the xfer scans for an OKAY that can never
        # come - observed as "the phone does not move on").
        last_p="$(journalctl -k --no-pager 2>/dev/null | grep "usb 1-1: Product: " | tail -1)"
        case "$last_p" in
          *"Fastboot2.0"*)
            log "c$c: skip snap (loader up)"
            ;;
          *)
            SNAP="snaps/snap_${c}_$(date +%H%M%S).ppm"
            if timeout 260 "$UV" run --with pyusb --no-project python3 oem_snap.py "$SNAP" >>"$LOG" 2>&1; then
              log "c$c: snap ok $(stat -c %s "$SNAP" 2>/dev/null) bytes"
            else
              log "c$c: snap failed"
            fi
            ;;
        esac
        # The magic CNXN should have reset the device; otherwise the
        # progress watchdog lands it in the loader. Wait, then reflash.
        for _ in $(seq 1 90); do
          lk_up && break
          sleep 1
        done
        if lk_up; then
          flash_now
        else
          log "c$c: no LK yet; waiting next event"
        fi
  fi
  # v193: stall rescue. A garbled or enumeration-failed boot never
  # produces a NEW event and never self-resets (the SP805 is fed), so
  # without this the engine would wait forever and need a physical
  # power-hold. After ~5 min of no fresh event, ask the device to crash
  # via the fastboot client; the kernel's responder or the loader both
  # accept `oem crash`, and the v63 chain lands it in the loader fastboot
  # where the flash path resumes. If the client cannot talk at all, note
  # it and keep the loop alive.
  STALL=$((STALL+1))
  if [ "$STALL" -ge 150 ]; then
    log "c$c: stall rescue; sending oem crash"
    timeout 30 fastboot -s "$S" oem crash >>"$LOG" 2>&1 || log "c$c: oem crash unavailable"
    STALL=0
  fi
  sleep 2
done
log "=== night engine v16 done ==="
