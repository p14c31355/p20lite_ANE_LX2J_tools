#!/bin/bash
# One-shot: wait for the next clean ANE fastboot enumeration, settle, collect ring tail.
set +m
LOG=logs/v306_collect_$(date +%H%M%S).log
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$LOG"; }
BASE=$(journalctl -k --no-pager | grep -c 'usb 1-1:')
log "baseline attach-count=$BASE"
for i in $(seq 1 200); do
  N=$(journalctl -k --no-pager | grep -c 'usb 1-1:')
  if [ "$N" -gt "$BASE" ]; then
    P=$(journalctl -k -n 40 --no-pager | grep 'usb 1-1: Product: ' | tail -1)
    log "new attach; product=$P"
    case "$P" in
      *'ANE fastboot'*)
        log "clean v306 boot; settle 30s then CNXN"
        sleep 30
        lk_up(){ lsusb -v -d 18d1:d00d 2>/dev/null | grep -qi "iProduct.*Fastboot2.0"; }
        UV="$(command -v uv || echo $HOME/.local/bin/uv)"
        timeout 60 "$UV" run --with pyusb --no-project python3 adb_cycle.py log rings_night/v306_collect.bin >>"$LOG" 2>&1
        RC=$?
        log "adb_cycle rc=$RC size=$(stat -c %s rings_night/v306_collect.bin 2>/dev/null || echo 0)"
        exit $RC
        ;;
    esac
    BASE=$N
  fi
  sleep 2
done
log "no clean boot in 400s"
exit 1
