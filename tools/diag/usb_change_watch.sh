#!/bin/bash
# USB state change watcher v2: silent baseline (no false CHANGE at start),
# then prints a CHANGE line only on a real transition. 8 h window.
set -u
prev=$(lsusb | grep -i "12d1\|18d1" | awk '{print $6}' | head -1)
prev="${prev:-NONE}"
echo "$(date +%H:%M:%S) watcher armed, baseline=$prev"
for i in $(seq 1 5760); do
    cur=$(lsusb | grep -i "12d1\|18d1" | awk '{print $6}' | head -1)
    cur="${cur:-NONE}"
    if [ "$cur" != "$prev" ]; then
        echo "$(date +%H:%M:%S) CHANGE: $prev -> $cur"
        prev="$cur"
    fi
    sleep 5
done
echo "$(date +%H:%M:%S) watcher window elapsed"
