#!/bin/bash
# Gather build up the ANE-LX2J toolkit repo from the working trees.
# Copy-only: sources stay untouched.
set -u
SRC=~/dev/p20-root
TMP=/tmp
DST=~/dev/p20lite_ANE_LX2J_tools

mkdir -p "$DST"/{docs,tools,artifacts,firmware,logs}

say() { echo "[$(date '+%H:%M:%S')] $*"; }

# 1) docs: the contracts, state, plans (p20-root + fullerene/docs + /tmp notes)
say "docs..."
cp -n "$SRC"/V21_STATE.md "$SRC"/ANE_ROOT_MAGISK_PLAN.md "$SRC"/VERIFICATION_LOOP.md \
      "$SRC"/REPORT_usb_harness_20261002.md "$SRC"/WINDOWS_CHECKLIST.txt "$DST/docs/" 2>/dev/null
cp -n ~/dev/fullerene/docs/ANE_BOOT_CONTRACT.md "$DST/docs/" 2>/dev/null
cp -n "$TMP"/ane-lx2j.*.md "$TMP"/ane_contract_s*.md "$TMP"/ane_bringup_*.md "$TMP"/ane_screen*.md "$DST/docs/" 2>/dev/null
cp -n "$TMP"/*.md "$DST/docs/tmp-notes/" 2>/dev/null || true
mkdir -p "$DST/docs/tmp-notes" && cp -n "$TMP"/*.md "$DST/docs/tmp-notes/" 2>/dev/null

# 2) tools: all the scripts that drive the device (top level of p20-root) + tools/
say "tools..."
cp -n "$SRC"/*.sh "$SRC"/*.S "$SRC"/*.py "$DST/tools/" 2>/dev/null
mkdir -p "$DST/tools/verify" && cp -n "$SRC"/tools/* "$DST/tools/verify/" 2>/dev/null
cp -n "$TMP"/stepmarks1*.py "$TMP"/gen_font.py "$TMP"/log_probe*.py "$DST/tools/verify/" 2>/dev/null

# 3) artifacts: the bootable probe/stepmark images
say "artifacts..."
cp -n "$SRC"/artifacts/*.img "$DST/artifacts/" 2>/dev/null
cp -n "$SRC"/artifacts/*.bin "$DST/artifacts/" 2>/dev/null

# 4) firmware: stock kernel + dtb + azrom archives (the user downloaded these)
say "firmware (this is the big one)..."
cp -n "$SRC"/firmware/kernel_stock.bin "$DST/firmware/" 2>/dev/null
mkdir -p "$DST/firmware/ane_dtb" && cp -n "$SRC"/firmware/ane_dtb/fdt.dtb "$SRC"/firmware/ane_dtb/fdt_properties.txt "$DST/firmware/ane_dtb/" 2>/dev/null
mkdir -p "$DST/firmware/azrom" && cp -n "$SRC"/firmware/azrom/*.zip "$SRC"/firmware/azrom/*.rar "$DST/firmware/azrom/" 2>/dev/null

# 5) logs: the automation logs + the screen captures worth keeping
say "logs..."
mkdir -p "$DST/logs/usb_runs" && cp -n "$SRC"/usb_runs/* "$DST/logs/usb_runs/" 2>/dev/null
mkdir -p "$DST/logs/screens" && cp -n "$TMP"/ane_cam*.jpg "$TMP"/textfix_hi.jpg "$TMP"/focus_check.jpg "$TMP"/probe_check.jpg "$DST/logs/screens/" 2>/dev/null

say "done"
du -sh "$DST"/* 2>/dev/null
