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
  [ "$(cat /sys/bus/usb/devices/1-1/product 2>/dev/null)" = "Fastboot2.0" ]
}

reboot_kernel_to_loader() {
  log "ANE fastboot present; reboot-bootloader (no combo)"
  timeout 20 fastboot -s "$S" reboot-bootloader >>"$LOG" 2>&1 || true
  for _ in $(seq 1 30); do
    if lk_up; then
      log "loader appeared after kernel reboot-bootloader"
      flash_now
      return 0
    fi
    sleep 1
  done
  log "kernel reboot-bootloader did not expose Fastboot2.0"
  return 1
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
  if [ "${SKIP_SAME_IMG:-0}" = "1" ]; then
    log "LK window; queued image already resident - rebooting only"
    timeout 20 fastboot -s "$S" reboot >>"$LOG" 2>&1 || true
    return 0
  fi
  log "LK window; flashing $IMG"
  timeout 180 fastboot -s "$S" flash kernel "$IMG" >>"$LOG" 2>&1
  timeout 20 fastboot -s "$S" reboot >>"$LOG" 2>&1
  STALL=0  # v11: restart the stall clock with every flash; the v193 rescue
           # misfired once (1007 15:27) by counting stall time across a live
           # replacement boot and crashing it.
  log "flashed + rebooted"
}

S=SCV7N18927000473
log "=== night engine v24 start img=$IMG cycles=$CYCLES ==="
# v19: start with an EMPTY baseline so the first loop iteration treats the
# attach already on the bus as a fresh event. v18 started with the last
# attach as EV and silently missed the boot that was in flight at restart
# (boot #27). A stale/dead attach processed this way simply fails its
# settle+CNXN and the loop moves on.
EV=""
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
      # v17/v18: the product line prints when the enumeration COMPLETES,
      # which can take many seconds (host retries + the -110 dance). Wait
      # (bounded, 90 s) for THIS attach's product before deciding - a
      # clean attach must not be skipped in its first 2 s (boot #22 was).
      # v18: --since anchored search instead of grep -A8 (the product line
      # can sit >8 lines below the attach line after error bursts).
      # v20: the --since anchor is the ATTACH's epoch (journal -o
      # short-unix), not now-8s - on a restart the gap can exceed the
      # window and hide a perfectly good product line (boot #27).
      log "c$c: attach in flight; waiting for product"
      _w0=$(journalctl -k -o short-unix --no-pager 2>/dev/null | grep "usb 1-1: new high-speed USB device number ${DEVNO} " | tail -1 | awk '{print $1}' | cut -d. -f1)
      [ -z "$_w0" ] && _w0=$(( $(date +%s) - 8 ))
      _w0=$(( _w0 - 2 ))
      for _w in $(seq 1 30); do
        sleep 3
        last_p="$(journalctl -k --since "@${_w0}" --no-pager 2>/dev/null | grep "usb 1-1: Product: " | tail -1)"
        [ -n "$last_p" ] && break
        # v23: a 50-byte descriptor set is a collectable boot even while
        # the string reads stall - do not burn the whole wait on it.
        _dsz=$(wc -c < /sys/bus/usb/devices/1-1/descriptors 2>/dev/null || echo 0)
        [ "$_dsz" -ge 50 ] && break
      done
      if [ -z "$last_p" ]; then
        # v21: the product line needs the string-descriptor reads; a boot
        # can be CLEAN at the descriptor level (the host's /sys dump shows
        # the full 50-byte form) while the strings never print. The CNXN
        # path does not need the strings - use the descriptor size as the
        # fallback gate: 50 bytes = collect (proven at 18:28, adb_manual_99).
        _dsz=$(wc -c < /sys/bus/usb/devices/1-1/descriptors 2>/dev/null || echo 0)
        if [ "$_dsz" -ge 50 ]; then
          log "c$c: no product but descriptors=${_dsz}B (clean form); proceeding"
          last_p="usb 1-1: Product: ANE fastboot (descriptor fallback)"
        else
          log "c$c: product-less attach; skip (no sessions possible, descriptors=${_dsz}B)"
          continue
        fi
      fi
      log "c$c: product arrived late: $last_p"
    fi
    if printf '%s' "$last_p" | grep -q "Љ"; then
      log "c$c: garbled product; skip sessions"
      continue
    fi
    if ! printf '%s' "$last_p" | grep -q "ANE fastboot"; then
      log "c$c: unexpected product; skip"
      continue
    fi
    # A clean kernel fastboot window is itself a no-button recovery point.
    # Do not wait for ADB or for the kernel's next watchdog: explicitly use
    # the same PMIC/LPM3 no-combo handoff as ane_cycle.sh, then flash the
    # queued image as soon as the loader enumerates.
    if [ "${SKIP_SAME_IMG:-0}" = "1" ]; then
      : # resident image - fall through to the collect path below
    elif reboot_kernel_to_loader; then
      sleep 5
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
        # v23: poll for the clean state (product "ANE fastboot" or the
        # /sys descriptors at >= 50 bytes), then ~9 s of grace to let the
        # string reads finish, then CNXN immediately. The launchd-era
        # boots die at the 16384-beat cap in 80-180 s real time, and the
        # v192 law says the FIRST conversation per window is the reliable
        # one - a fixed settle loses the race.
        _grace=0
        for _s in $(seq 1 20); do
          last_p="$(journalctl -k -n 40 --no-pager 2>/dev/null | grep "usb 1-1: Product: " | tail -1)"
          case "$last_p" in
            *"Fastboot2.0"*) break ;;
          esac
          _dsz=$(wc -c < /sys/bus/usb/devices/1-1/descriptors 2>/dev/null || echo 0)
          if printf '%s' "$last_p" | grep -q "ANE fastboot" || [ "$_dsz" -ge 50 ]; then
            _grace=$((_grace+1))
            [ "$_grace" -ge 3 ] && break
          else
            _grace=0
          fi
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
        if [ "$CNXN_OK" = "1" ] && [ "${SKIP_SAME_IMG:-0}" = "1" ]; then
          log "c$c: collection ok; cycling to loader"
          timeout 20 fastboot -s "$S" reboot-bootloader >>"$LOG" 2>&1 || true
          for _ in $(seq 1 30); do lk_up && break; sleep 1; done
          continue
        fi
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
  # v331 autonomy: a long-lived ANE fastboot with no new attach event is
  # a live-but-stale boot (the engine's event trigger never fires). When
  # the ADB probe is also failing (the wedged EP1 case), force the
  # reboot-bootloader cycle: the LK comes up, the flash resumes, the
  # overnight loop keeps turning without a physical hold.
  if [ "$STALL" -eq 75 ]; then
    if [ "$(cat /sys/bus/usb/devices/1-1/product 2>/dev/null)" = "ANE fastboot" ]; then
      log "c$c: stale ANE fastboot; forcing reboot-bootloader"
      reboot_kernel_to_loader || log "c$c: forced reboot failed; continuing"
      STALL=0
    fi
  fi
  sleep 2
done
log "=== night engine v24 done ==="
