#!/usr/bin/env python3
"""v11 engine transform: night_engine.sh -> night_engine_v11.sh

Three fixes:
 1. version strings v10 -> v11
 2. flash_now(): STALL=0 on every flash (the v193 rescue must never count
    stall time across a live replacement boot; it crashed a fresh boot on
    2026-10-07 15:27).
 3. the 180 s settle is now a watch loop that aborts the moment the kernel
    dies (loader "Fastboot2.0" takes over) and re-flashes immediately.
"""
src = open('night_engine.sh').read()
edits = [
    ("log \"=== night engine v10 start img=$IMG cycles=$CYCLES ===\"",
     "log \"=== night engine v11 start img=$IMG cycles=$CYCLES ===\""),
    ("log \"=== night engine v10 done ===\"",
     "log \"=== night engine v11 done ===\""),
    ('''  timeout 20 fastboot -s "$S" reboot >>"$LOG" 2>&1
  log "flashed + rebooted"''',
     '''  timeout 20 fastboot -s "$S" reboot >>"$LOG" 2>&1
  STALL=0  # v11: restart the stall clock with every flash; the v193 rescue
           # misfired once (1007 15:27) by counting stall time across a live
           # replacement boot and crashing it.
  log "flashed + rebooted"'''),
    ('''        sleep 180
        mkdir -p rings_night''',
     '''        # v11: settle ~180 s for the post-bringup window, but abort the
        # wait the moment the kernel dies (the loader's "Fastboot2.0" takes
        # over) so a dead boot is re-flashed without the full wait.
        for _s in $(seq 1 90); do
          last_p="$(journalctl -k --no-pager 2>/dev/null | grep "usb 1-1: Product: " | tail -1)"
          case "$last_p" in
            *"Fastboot2.0"*) break ;;
          esac
          sleep 2
        done
        if lk_up; then
          log "c$c: settle aborted; loader up"
          flash_now
          sleep 5
          continue
        fi
        mkdir -p rings_night'''),
]
out = src
for old, new in edits:
    n = out.count(old)
    if n != 1:
        raise SystemExit(f"anchor count {n} for: {old[:60]!r}")
    out = out.replace(old, new)
open('night_engine_v11.sh', 'w').write(out)
print("night_engine_v11.sh written")
