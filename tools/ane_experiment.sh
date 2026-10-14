#!/bin/bash
# One Fullerene boot attempt on the ANE-LX2J, with everything the host can see.
#
# Usage:
#   ane_experiment.sh <boot-image> <label> [--flash] [--wait SECONDS]
#
# Default is `fastboot boot` (RAM-boots the image, leaves the flashed stock
# kernel in place so any crash returns to Android by itself). --flash writes the
# kernel partition first; that is the path already proven on this device, but it
# needs hands on the power button if the image wedges.
#
# The observation channel is the bus: with no serial and a screen nobody is
# watching, the pattern of USB transitions is the measurement, and the pstore
# readback (ane_read_pstore.sh) is the payload.
set -u
cd "$(dirname "$0")" || exit 1
IMAGE=${1:?usage: ane_experiment.sh <image> <label> [--flash] [--wait N]}
LABEL=${2:?label required}
MODE=boot
WAIT=150
shift 2
while [ $# -gt 0 ]; do
  case "$1" in
    --flash) MODE=flash ;;
    --wait) WAIT=$2; shift ;;
    *) echo "unknown option $1"; exit 2 ;;
  esac
  shift
done

[ -f "$IMAGE" ] || { echo "no such image: $IMAGE"; exit 2; }
mkdir -p artifacts
LOG=artifacts/run_${LABEL}_$(date +%m%d_%H%M%S).log
: > "$LOG"
log() { echo "$@" | tee -a "$LOG"; }
probe() {
  USB=$(lsusb 2>/dev/null | grep -iE "12d1|18d1|1234|2c7c" | sed 's/.*ID //' | head -1)
  FB=$(timeout 3 fastboot devices 2>/dev/null | awk '{print $1}')
  AD=$(timeout 3 adb devices 2>/dev/null | awk 'NR==2{print $2}')
  echo "usb=[$USB] fb=[$FB] adb=[$AD]"
}

log "== experiment $LABEL  ($(date))"
log "image: $IMAGE ($(stat -c %s "$IMAGE") bytes)  mode: $MODE"

# --- 1. reach fastboot -------------------------------------------------------
STATE=none
timeout 15 adb devices 2>/dev/null | awk 'NR==2{print $2}' | grep -q device && STATE=adb
if [ "$STATE" = none ] && timeout 10 fastboot devices 2>/dev/null | grep -q .; then STATE=fastboot; fi
log "initial state: $STATE  $(probe)"
if [ "$STATE" = adb ]; then
  timeout 60 adb reboot bootloader 2>&1 | tee -a "$LOG"
  for _ in $(seq 1 30); do
    sleep 2
    timeout 8 fastboot devices 2>/dev/null | grep -q . && break
  done
fi
if ! timeout 10 fastboot devices 2>/dev/null | grep -q .; then
  log "ERROR: no fastboot device; cannot run"
  exit 1
fi
log "fastboot ok: $(probe)"
timeout 20 fastboot oem lock-state info 2>&1 | tee -a "$LOG" || true

# --- 2. hand the image to the loader ----------------------------------------
if [ "$MODE" = boot ]; then
  log "== fastboot boot"
  timeout 420 fastboot boot "$IMAGE" 2>&1 | tee -a "$LOG"
  RC=${PIPESTATUS[0]}
  log "(fastboot boot exit $RC)"
else
  log "== fastboot flash kernel"
  timeout 420 fastboot flash kernel "$IMAGE" 2>&1 | tee -a "$LOG"
  RC=${PIPESTATUS[0]}
  log "(fastboot flash exit $RC)"
  sleep 1
  timeout 60 fastboot reboot 2>&1 | tee -a "$LOG" || true
fi

# --- 3. watch -----------------------------------------------------------------
log "== watching for ${WAIT}s"
LAST=""
for i in $(seq 1 $((WAIT / 2))); do
  NOW=$(probe)
  if [ "$NOW" != "$LAST" ]; then
    printf '%3d %s %s\n' "$i" "$(date +%T)" "$NOW" >> "$LOG"
    LAST="$NOW"
  fi
  sleep 2
done
log "== transitions seen"
cat "$LOG" | grep -E "^ *[0-9]+ [0-9:]+ usb=" | tail -25
log "== done"
