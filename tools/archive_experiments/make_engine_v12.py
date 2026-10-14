#!/usr/bin/env python3
"""v12 engine transform: night_engine_v11.sh -> night_engine_v12.sh

1. version strings v11 -> v12
2. settle: the v11 loop ran journalctl (full) per iteration and stretched
   180 s to ~280 s real, missing the ~4 m 45 s bad-boot window. v12 uses
   cheap bounded journal tail checks: 40 x 3 s ~ 130 s real.
3. capture the host-side descriptor snapshot (forensics_snap.sh) for every
   boot event - works for garbled boots too (no USB session needed).
"""
src = open("night_engine_v11.sh").read()
edits = [
    ('log "=== night engine v11 start img=$IMG cycles=$CYCLES ==="',
     'log "=== night engine v12 start img=$IMG cycles=$CYCLES ==="'),
    ('log "=== night engine v11 done ==="',
     'log "=== night engine v12 done ==="'),
    ('''        # v11: settle ~180 s for the post-bringup window, but abort the
        # wait the moment the kernel dies (the loader's "Fastboot2.0" takes
        # over) so a dead boot is re-flashed without the full wait.
        for _s in $(seq 1 90); do
          last_p="$(journalctl -k --no-pager 2>/dev/null | grep "usb 1-1: Product: " | tail -1)"
          case "$last_p" in
            *"Fastboot2.0"*) break ;;
          esac
          sleep 2
        done''',
     '''        # v12: settle ~120 s real (bad boots die at ~4 m 45 s; v11's
        # unbounded journalctl loop stretched 180 s to ~280 s and missed
        # the window). Cheap bounded journal tail checks, early abort the
        # moment the loader's "Fastboot2.0" takes over.
        for _s in $(seq 1 40); do
          last_p="$(journalctl -k -n 40 --no-pager 2>/dev/null | grep "usb 1-1: Product: " | tail -1)"
          case "$last_p" in
            *"Fastboot2.0"*) break ;;
          esac
          sleep 3
        done'''),
    ('''    log "c$c: usb event: $CUR"
    case "$CUR" in''',
     '''    log "c$c: usb event: $CUR"
    # v12: host-side descriptor forensics for every boot (works for
    # garbled boots too - no USB session needed).
    bash forensics_snap.sh >>"$LOG" 2>&1
    case "$CUR" in'''),
]
out = src
for old, new in edits:
    n = out.count(old)
    if n != 1:
        raise SystemExit(f"anchor count {n} for: {old[:70]!r}")
    out = out.replace(old, new)
open("night_engine_v12.sh", "w").write(out)
print("night_engine_v12.sh written")
