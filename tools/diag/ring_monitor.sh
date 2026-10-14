#!/usr/bin/env bash
# State emitter for the Hermes cron monitor (ring collection overseer).
# Prints a deterministic-ish snapshot: unchanged output = no agent wake.
# Changes (new rings, new engine events, new usb products, boot quality,
# engine liveness) wake the agent with the diff.
cd "$HOME/dev/p20-root" || exit 0

L="$(ls -t logs/night_*.log 2>/dev/null | head -1)"
echo "== engine log: $L"
grep -E "LK window|flashed \+|usb event|garbled|ring bytes|raw:|cnxn reply|adb attempt|ring xfer|kernel gone|settle aborted" "$L" 2>/dev/null | tail -14

echo "== boot quality (journal usb 1-1 tail):"
journalctl -k --no-pager 2>/dev/null | grep "usb 1-1" | tail -6

echo "== engine proc:"
pgrep -af "night_engine" | head -2

echo "== collected rings (nonzero):"
find rings_night -name 'adb_*.bin' -size +0c -printf '%f %s\n' 2>/dev/null | sort | tail -8

echo "== newest shots:"
ls -t shots/*.jpg 2>/dev/null | head -3

