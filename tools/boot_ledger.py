#!/usr/bin/env python3
"""Boot-quality ledger from the host kernel log.

Segments today's `usb 1-1` journal lines into per-attempt records and
classifies each: CLEAN / GARBLED / LOADER / FAILED. Appends new device
numbers to forensics/boot_ledger.tsv (idempotent by device number).

Run: python3 boot_ledger.py [--since "16:00"]
"""
import re
import subprocess
import sys
from datetime import datetime

since = "15:00"
for i, a in enumerate(sys.argv):
    if a == "--since" and i + 1 < len(sys.argv):
        since = sys.argv[i + 1]

out = subprocess.run(
    ["journalctl", "-k", "--since", since, "--no-pager"],
    capture_output=True, text=True,
).stdout

# Collect usb 1-1 events in order.
events = []
for line in out.splitlines():
    if "usb 1-1" not in line and "usb usb1-port1" not in line:
        continue
    m = re.search(r"(\d{2}:\d{2}:\d{2}).*?usb 1-1: (.*)", line)
    if not m:
        m2 = re.search(r"(\d{2}:\d{2}:\d{2}).*?(usb usb1-port1: .*)", line)
        if m2:
            events.append((m2.group(1), "PORT", m2.group(2)))
        continue
    events.append((m.group(1), "DEV", m.group(2)))

# Segment by "new high-speed USB device number N".
recs = []
cur = None
for t, kind, msg in events:
    m = re.match(r"new high-speed USB device number (\d+)", msg)
    if m:
        if cur:
            recs.append(cur)
        cur = {"dev": int(m.group(1)), "start": t, "flags": set(), "product": ""}
        continue
    if cur is None:
        continue
    if "Product: " in msg:
        cur["product"] = msg.split("Product: ", 1)[1]
    if "error -" in msg or "unable to" in msg or "can't read" in msg:
        cur["flags"].add("ERR")
    if "New USB device found" in msg:
        cur["flags"].add("FOUND")
    if "attempt power cycle" in msg:
        cur["flags"].add("PCYCLE")
if cur:
    recs.append(cur)

rows = []
for r in recs:
    if r["product"] == "Fastboot2.0":
        q = "LOADER"
    elif r["product"] == "ANE fastboot":
        q = "CLEAN" if "ERR" not in r["flags"] else "CLEAN-late-err"
    elif r["product"]:
        q = "GARBLED"
    elif "FOUND" in r["flags"]:
        q = "FOUND-noprod"
    else:
        q = "FAILED"
    rows.append((r["dev"], r["start"], q, r["product"] or "-", ",".join(sorted(r["flags"]))))

path = "forensics/boot_ledger.tsv"
import os
os.makedirs("forensics", exist_ok=True)
seen = set()
if os.path.exists(path):
    with open(path) as f:
        for line in f:
            parts = line.split("\t")
            if len(parts) >= 2 and parts[0].isdigit():
                seen.add(parts[0] + "|" + parts[1])

with open(path, "a") as f:
    if not seen:
        f.write("dev\tstart\tclass\tproduct\tflags\n")
    for dev, start, q, prod, flags in rows:
        key = str(dev) + "|" + start
        if key not in seen:
            f.write(f"{dev}\t{start}\t{q}\t{prod}\t{flags}\n")
            seen.add(key)
print(f"{len(rows)} records parsed; ledger updated ({len(seen)} total)")
