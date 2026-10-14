#!/bin/bash
# morning_check.sh: decode the newest collected ring and print the launchd
# verdict at a glance. Run first thing after the v143 boot's grab lands.
cd ~/dev/p20-root || exit 1
R=$(ls -t rings_night/ring_c*.bin 2>/dev/null | head -1)
echo "== newest ring: ${R:-none} =="
[ -n "$R" ] || { echo "no ring yet - waiting for the engine's grab"; exit 1; }
echo "== size: $(stat -c %s "$R") bytes =="
python3 decode_ring.py "$R" | tail -40
echo
echo "== keyword counts (full file) =="
python3 - "$R" <<'EOF'
import sys
data = open(sys.argv[1], "rb").read()
for kw in (b"MARK:", b"MARK", b"USER-LAUNCHD", b"STAGING-LENGTH", b"ERET", b"EL0",
           b"SVC", b"INTERPRETER", b"PROBE_DONE", b"IMG READ"):
    print(f"  {kw.decode():16s} {data.count(kw)}")
EOF
