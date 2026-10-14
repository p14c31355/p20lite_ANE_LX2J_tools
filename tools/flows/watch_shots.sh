#!/bin/bash
# Watch the phone drop folder and emit one line per newly arrived photo.
# Run with notify=["[shots]"] so each line pings the agent.
cd "$(dirname "$0")/shots" || exit 1
last=$(ls -t 2>/dev/null | head -1)
while true; do
  newest=$(ls -t 2>/dev/null | head -1)
  if [ -n "$newest" ] && [ "$newest" != "$last" ]; then
    last="$newest"
    echo "[shots] new file: $(pwd)/$newest"
  fi
  sleep 2
done
