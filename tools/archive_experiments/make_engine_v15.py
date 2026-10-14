#!/usr/bin/env python3
"""v15 engine transform: night_engine_v14.sh -> night_engine_v15.sh

The bug it fixes: last_event() returned the last "Product:" line; a
product-less attach (kernel strings never printed, dev 49 at 17:20)
returned the PREVIOUS attach's line, so CUR == EV and the whole boot was
skipped in silence (no snapshot, no log, no recovery).

v15: trigger on the attach line itself ("new high-speed USB device
number N" - unique per attach, always printed); classify by the product
line at fire time (loader / garbled / product-less / clean).
"""
import sys

src = open("night_engine_v14.sh").read()

# 1. version strings
src = src.replace(
    'log "=== night engine v14 start img=$IMG cycles=$CYCLES ==="',
    'log "=== night engine v15 start img=$IMG cycles=$CYCLES ==="')
src = src.replace('log "=== night engine v14 done ==="',
                  'log "=== night engine v15 done ==="')

# 2. last_event -> attach-line trigger
old_le = '''last_event() {
  # The ONLY trigger that matters is the kernel's own enumeration completing.
  # The loader's fastboot shares VID:PID 18d1:d00d. The loader's Product is
  # always the literal "Fastboot2.0"; the kernel's varies ("ANE fastboot"
  # when its string reply lands cleanly, garbage like "Љ" when the loader's
  # EP0 leftovers leak into the string read). So: the last enumerated device
  # whose Product is NOT "Fastboot2.0" is the kernel - fire on that.
  journalctl -k --no-pager -n 600 2>/dev/null \\
    | grep -A6 "usb 1-1: New USB device found" \\
    | grep "usb 1-1: Product: " | grep -v "Product: Fastboot2.0" | tail -1
}'''
new_le = '''last_event() {
  # v15: trigger on the ATTACH line itself ("new high-speed USB device
  # number N" - every attach prints one, each is unique). The old
  # product-string trigger went STALE on product-less attaches (the
  # kernel's strings never printed) and returned the previous attach's
  # line, so whole boots were skipped in silence (dev 49, 17:20).
  journalctl -k --no-pager -n 600 2>/dev/null \\
    | grep "usb 1-1: new high-speed USB device number" | tail -1
}'''
if old_le not in src:
    sys.exit("last_event anchor missing")
src = src.replace(old_le, new_le)

# 3. classifier replaces the case-opener + old Љ check
old_case = '''    case "$CUR" in
      *"USB disconnect"*) sleep 2; continue ;;
      *"Product: "*)
        # The kernel is enumerated RIGHT NOW.
        #
        # v188: garbled-product boots ("Љ") have broken descriptors - pyusb
        # cannot even find EP1 (Invalid endpoint address 0x81), so every
        # session attempt is dead weight. Only clean "ANE fastboot"/clean
        # strings offer working endpoints; skip the rest fast and wait for
        # the next boot.
        if printf '%s' "$CUR" | grep -q "Љ"; then
          log "c$c: garbled product; skip sessions"
          continue
        fi'''
new_case = '''    # v15: CUR is the attach line; classify via the product line.
    last_p="$(journalctl -k -n 600 --no-pager 2>/dev/null | grep "usb 1-1: Product: " | tail -1)"
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
    fi'''
if old_case not in src:
    sys.exit("case-opener anchor missing")
src = src.replace(old_case, new_case)

# 4. remove the case closer (the case no longer exists; its `;;` and
#    `esac` must go, or bash dies with a syntax error)
old_close = '''        if lk_up; then
          flash_now
        else
          log "c$c: no LK yet; waiting next event"
        fi
        ;;
    esac
  fi'''
new_close = '''        if lk_up; then
          flash_now
        else
          log "c$c: no LK yet; waiting next event"
        fi
  fi'''
if old_close not in src:
    sys.exit("case-closer anchor missing")
src = src.replace(old_close, new_close)

open("night_engine_v15.sh", "w").write(src)
print("night_engine_v15.sh written:", len(src), "bytes")
