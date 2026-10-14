#!/usr/bin/env bash
set -euo pipefail
SER=SCV7N18927000473
USB=/sys/bus/usb/devices/1-1
IMG=/home/placeless/dev/p20-root/artifacts/fullerene-ane-dctl-enum-gated-v1.img
printf 'watch-start %s image=%s\n' "$(date -Is)" "$IMG"
test -f "$IMG"
# One shot: fail closed if any identity field is absent or changes.
for ((i=0; i<900; i++)); do
  if [[ -r "$USB/idVendor" && -r "$USB/idProduct" && -r "$USB/product" && -r "$USB/serial" ]]; then
    vendor=$(<"$USB/idVendor") || continue
    pid=$(<"$USB/idProduct") || continue
    product=$(<"$USB/product") || continue
    serial=$(<"$USB/serial") || continue
    if [[ "$vendor:$pid:$product:$serial" == "18d1:d00d:Fastboot2.0:$SER" ]]; then
      devices=$(timeout 4 fastboot devices 2>/dev/null) || { sleep 1; continue; }
      if [[ "$devices" == *"$SER"* ]]; then
        printf 'identity-confirmed %s %s\n' "$(date -Is)" "$vendor:$pid:$product:$serial"
        # Recheck immediately before the write; never flash an ANE kernel responder.
        [[ "$(<"$USB/product")" == Fastboot2.0 && "$(<"$USB/serial")" == "$SER" && "$(<"$USB/idVendor")" == 18d1 && "$(<"$USB/idProduct")" == d00d ]] || exit 2
        timeout 35 fastboot -s "$SER" flash kernel "$IMG"
        printf 'flash-ok %s\n' "$(date -Is)"
        timeout 15 fastboot -s "$SER" reboot
        printf 'reboot-ok %s\n' "$(date -Is)"
        exit 0
      fi
    fi
  fi
  sleep 1
done
printf 'watch-expired %s\n' "$(date -Is)" >&2
exit 1
