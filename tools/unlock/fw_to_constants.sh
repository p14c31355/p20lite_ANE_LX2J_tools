#!/bin/bash
# Firmware package -> KERNEL image -> symbol addresses -> the two constants the
# exploit hardcodes.
#
# Usage: fw_to_constants.sh <firmware.rar|zip|UPDATE.APP|*.app> [workdir]
#
# Accepts whatever shape the package arrives in:
#   - a full dload .rar/.zip containing Software/dload/update_sd.zip
#   - the inner update_sd_<model>.zip (holds update_<model>.app)
#   - a bare *.app / UPDATE.APP
# It unpacks to the workdir, finds the first .app payload, scans it for the KERNEL
# block, turns that into an ELF with vmlinux-to-elf, and prints the addresses of
# fair_sched_class and avc_cache - the two values the exploit needs.
set -u
IN="${1:?usage: fw_to_constants.sh <firmware> [workdir]}"
W="${2:-/tmp/syms_fw}"
HERE="$(cd "$(dirname "$0")" && pwd)"
VMLINUX="$HERE/.venv-sym/bin/vmlinux-to-elf"
[ -x "$VMLINUX" ] || VMLINUX="vmlinux-to-elf"

mkdir -p "$W"
echo "############ 1. unpack $IN"
rm -rf "$W/unpack"; mkdir -p "$W/unpack"
case "$IN" in
  *.rar)  /home/placeless/opt/7zz/7zz x -y -o"$W/unpack" "$IN" >/dev/null || exit 1 ;;
  *.zip)  unzip -o -q "$IN" -d "$W/unpack" || exit 1 ;;
  *)      cp "$IN" "$W/unpack/" ;;
esac
echo "  top of the tree:"; find "$W/unpack" -maxdepth 4 -type f -printf '    %10s  %p\n' | sort -k2 | head -20

echo
echo "############ 2. find the app payload"
APP=$(find "$W/unpack" -type f \( -iname "*.app" -o -iname "UPDATE.APP" \) -printf '%s\t%p\n' | sort -rn | head -1 | cut -f2)
if [ -z "$APP" ]; then
  echo "  no .app found - looking for another zip to recurse into"
  INNER=$(find "$W/unpack" -type f -iname "*.zip" -printf '%s\t%p\n' | sort -rn | head -1 | cut -f2)
  [ -n "$INNER" ] || { echo "  nothing to scan"; exit 1; }
  echo "  recursing into $INNER"; exec bash "$0" "$INNER" "$W/inner"
fi
echo "  app: $APP ($(stat -c%s "$APP") bytes)"

echo
echo "############ 3. scan every header and extract KERNEL (+ symbols)"
python3 "$HERE/scan_app_all.py" "$APP" "$W/kern"
KIMG="$W/kern/kernel.img"
[ -f "$KIMG" ] || { echo "  KERNEL block not found"; exit 1; }
ls -la "$KIMG" "$W/kern/kernel.elf" 2>/dev/null
echo
echo "### cross-check against what the exploit ships today:"
echo "###   FAIR_SCHED_CLASS ffffff8008f78408"
echo "###   AVC_CACHE        ffffff800a2d4c40"
echo "### (8.0.0.110(C635) measured: ffffff8008f48408 / ffffff800a276c40)"
