#!/usr/bin/env python3
"""v21 engine transform: night_engine_v20.sh -> night_engine_v21.sh

Proven at 18:28: a boot can be CLEAN at the descriptor level (the host's
/sys/bus/usb/devices/1-1/descriptors shows the full 50-byte form) while
its string-descriptor reads stall and the product line never prints.
The v20 product-gate declared such a boot product-less and skipped it;
a manual adb_cycle then COLLECTED it (ring 2049 bytes, adb_manual_99).

v21: after the bounded wait fails, fall back to the descriptor-size gate:
50+ bytes = clean form -> proceed; anything else -> skip.
"""

src = open("night_engine_v20.sh").read()

old = '''      if [ -z "$last_p" ]; then
        log "c$c: product-less attach; skip (no sessions possible)"
        continue
      fi
      log "c$c: product arrived late: $last_p"'''
new = '''      if [ -z "$last_p" ]; then
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
      log "c$c: product arrived late: $last_p"'''
assert old in src, "v20 skip block not found"
src = src.replace(old, new, 1)

src = src.replace("night engine v20 start", "night engine v21 start")
src = src.replace("night engine v20 done", "night engine v21 done")

open("night_engine_v21.sh", "w").write(src)
print("night_engine_v21.sh written,", len(src), "chars")
