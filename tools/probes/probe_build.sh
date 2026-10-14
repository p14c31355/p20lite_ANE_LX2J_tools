#!/bin/bash
# Probe which strings exist in the kernel image vs which SHOULD exist.
IMG=/tmp/v202.Image
echo "== v202 string probes:"
for pat in "ud: q=" "usb: attach=" "enumeration never configured" "tick budget exhausted" \
           "WD: RECONNECT" "WD: NO ENUM" "usb_reconnect" "SET_CONFIGURATION" "config_value"; do
  printf "%-30s: %s\n" "$pat" "$(strings "$IMG" | grep -c -- "$pat")"
done
echo
echo "== all 'watchdog' strings:"
strings "$IMG" | grep -i watchdog | head -8
echo
echo "== all 'attach' strings:"
strings "$IMG" | grep -i attach | head -8
echo
echo "== Cargo.toml [[bin]] targets:"
grep -A3 '\[\[bin\]\]' ~/dev/fullerene/fullerene-kernel/Cargo.toml | head -40
echo
echo "== files in the fullerene-kernel src listing:"
ls ~/dev/fullerene/fullerene-kernel/src/ | head -30
