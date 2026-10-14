#!/bin/bash
# ane_cycle.sh [image] - the standard ANE no-combo cycle (v29+ kernels).
#
# Without an argument: drains the one-time stale reply the loader leaves in
# the IN FIFO, then verifies getvar + dumps the durable log over USB.
# With an image: reboot-bootloader (no key combo - the PMIC reason register +
# LPM3 NMI chain), flashes through the loader, boots, then the same checks.
#
# Usage:  bash ane_cycle.sh                          # just verify
#         bash ane_cycle.sh artifacts/foo-stock.img  # flash + verify
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
FASTBOOT=$(command -v fastboot || echo /usr/bin/fastboot)
UV=/home/placeless/.hermes/bin/uv
say(){ echo "[$(date +%H:%M:%S)] $*"; }

prod(){ for f in /sys/bus/usb/devices/*/product; do
    d=$(dirname "$f")
    v=$(cat "$d/idVendor" 2>/dev/null); p=$(cat "$d/idProduct" 2>/dev/null)
    if [ "$v" = 18d1 ] && [ "$p" = d00d ]; then cat "$f"; return; fi
  done; }

wait_prod(){ # want tries
  local want=$1 tries=$2 i P=""
  for i in $(seq 1 "$tries"); do
    P=$(prod)
    [ "$P" = "$want" ] && break
    sleep 5
  done
  echo "$P"
}

drain(){ :; } # (superseded by the pyusb-based sacrifice below)

sacrifice(){ # The first push after boot drains the loader's stale TX-FIFO
             # bytes ahead of the real reply, so the first fastboot session
             # of a boot sees garbage. Consume it here: write one throwaway
             # command and read until silence (a real client would bail at
             # the bad status byte and leave the rest of the stale behind;
             # the kernel's first-reply sweep inflates this transfer to
             # cover the whole stale plus the reply). Also eats any leftover
             # the previous session did not consume (killed streams leave
             # their tail and final OKAY behind), so every real session in
             # this chain starts on a clean pipe. Settle once after boot:
             # right after enumeration the device can transiently report
             # EBUSY while udev probes it.
  if [ -z "${SETTLED:-}" ]; then sleep 4; SETTLED=1; fi
  "$UV" run --no-project --with pyusb python3 - <<'EOF' 2>/dev/null | tail -1
import time
import usb.core
import usb.util
dev = usb.core.find(idVendor=0x18D1, idProduct=0xD00D)
if not dev:
    print("sacrifice: device not found")
    raise SystemExit
for attempt in range(8):
    try:
        try:
            dev.detach_kernel_driver(0)
        except Exception:
            pass
        dev.set_configuration()
        usb.util.claim_interface(dev, 0)
        dev.write(0x01, b"getvar:version")
        break
    except Exception as e:
        if attempt == 7:
            print(f"sacrifice: setup failed: {e}")
            raise SystemExit
        time.sleep(1.5)
# Let the device generate its reply before reading, so this process eats
# BOTH any leftover and its own reply - otherwise one reply always stays
# behind and every later session runs one exchange behind.
time.sleep(0.6)
got = b""
strikes = 0
for _ in range(45):
    try:
        r = bytes(dev.read(0x81, 1024, timeout=250))
    except Exception:
        strikes += 1
        if strikes >= 3:
            break
        continue
    if not r:
        strikes += 1
        if strikes >= 3:
            break
        continue
    strikes = 0
    got += r
print(f"sacrifice ate {len(got)}B: ...{got[-32:]!r}" if got else "sacrifice: no reply")
EOF
}

IMG=${1:-}
P=$(prod); say "current device: ${P:-none}"

if [ -n "$IMG" ]; then
  if [ "$P" = "ANE fastboot" ]; then
    say "reboot-bootloader (no combo)"
    timeout 20 "$FASTBOOT" -s "$S" reboot-bootloader 2>&1 | tail -1
    P=$(wait_prod "Fastboot2.0" 24)
    say "loader: ${P:-none}"
    if [ "$P" != "Fastboot2.0" ]; then say "LK NOT REACHED"; exit 1; fi
  elif [ "$P" != "Fastboot2.0" ]; then
    say "no device yet - COMBO now, waiting for the loader (up to 4 min)"
    P=$(wait_prod "Fastboot2.0" 48)
    say "loader: ${P:-none}"
    if [ "$P" != "Fastboot2.0" ]; then say "LK NOT SEEN - abort"; exit 1; fi
  fi
  say "flashing $IMG"
  timeout 180 "$FASTBOOT" -s "$S" flash kernel "$IMG" 2>&1 | tail -2
  timeout 60 "$FASTBOOT" -s "$S" reboot 2>&1 | tail -1
  P=$(wait_prod "ANE fastboot" 24)
  say "kernel: ${P:-none}"
  if [ "$P" != "ANE fastboot" ]; then say "KERNEL NOT SEEN"; exit 2; fi
  sleep 3
fi

if [ "$P" = "ANE fastboot" ]; then
  say "getvar version (sacrifice first: eats boot stale / leftovers)"
  drain
  sacrifice
  timeout 15 "$FASTBOOT" -s "$S" getvar version 2>&1 | tail -2
  say "getvar product"
  sacrifice
  timeout 15 "$FASTBOOT" -s "$S" getvar product 2>&1 | tail -2
  say "oem log (last 12 lines)"
  sacrifice
  timeout 90 "$FASTBOOT" -s "$S" oem log 2>&1 | tail -14
fi
say "DONE"
