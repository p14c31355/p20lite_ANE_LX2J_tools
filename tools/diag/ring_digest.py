#!/usr/bin/env python3
"""ring_digest v1 - classify ANE ring files for the zero-human loop.

Reads rings_night/adb_*.bin, extracts the meaningful lines (EM probe, LAUNCHD,
WD, instruments), classifies the capture, and appends one JSON line per file
to rings_night/digest.jsonl. Idempotent: already-digested files are skipped.

Usage:
  python3 ring_digest.py                # digest any new rings, print summary
  python3 ring_digest.py --all          # re-digest everything
  python3 ring_digest.py <file.bin>     # digest one file (prints only)
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
RINGS = os.path.join(ROOT, "rings_night")
INDEX = os.path.join(RINGS, "digest.jsonl")

RE_EM = re.compile(r"EM:\s*([A-Z0-9_]+)=(0X[0-9A-F]+|\d+)")
RE_FNV = re.compile(r"EX_FNV=(0X[0-9A-F]+)")


def digest_one(path):
    data = open(path, "rb").read()
    text = data.decode("ascii", "replace")
    # significant lines: drop pure IRQ-trace / stage-letter noise
    sig = []
    n_lines = 0
    for raw in text.replace("\r\n", "\n").split("\n"):
        line = raw.strip("\x00").strip()
        n_lines += 1
        if not line:
            continue
        keep = any(k in line for k in ("EM:", "LAUNCHD", "WD:", "UD8:", "DS:"))
        if not keep and ("IRQ" in line or re.fullmatch(r"\.*[A-Z.]{1,8}", line)):
            continue
        sig.append(line)

    joined = "\n".join(sig)
    em = {m.group(1): m.group(2) for m in RE_EM.finditer(joined)}
    fnv = RE_FNV.search(joined)
    printable = sum(1 for c in text if 32 <= ord(c) < 127 or c in "\r\n\t")
    pct = printable / max(1, len(text))

    has_probe = em.get("PROBE_DONE", "") in ("1", "0X1", "0X0000000000000001")
    has_launchd = "LAUNCHD" in joined
    has_stall = "BOOT PROGRESS STALLED" in joined
    nl = text.count("\n") + text.count("\r")
    newline_ratio = nl / max(1, len(text) // 4)

    if len(data) == 0:
        cls = "empty"
    elif pct < 0.5:
        cls = "binary"
    elif newline_ratio > 0.9 and not sig:
        cls = "flood"
    elif has_probe or has_launchd:
        cls = "bootlog"
    else:
        cls = "partial"

    return {
        "file": os.path.basename(path),
        "bytes": len(data),
        "class": cls,
        "probe_done": has_probe,
        "launchd_pre": has_launchd,
        "stall": has_stall,
        "ex_fnv": fnv.group(1) if fnv else None,
        "em_count": len(em),
        "sig_lines": len(sig),
        "note": (sig[-3:] if sig else []),
    }


def main():
    args = sys.argv[1:]
    if args and args[0] != "--all":
        for p in args:
            print(json.dumps(digest_one(p), ensure_ascii=False))
        return

    seen = set()
    if args != ["--all"] and os.path.exists(INDEX):
        for ln in open(INDEX):
            try:
                seen.add(json.loads(ln)["file"])
            except Exception:
                pass

    files = sorted(
        (f for f in os.listdir(RINGS) if f.startswith("adb_") and f.endswith(".bin")),
        key=lambda f: int(re.sub(r"\D", "", f) or 0),
    )
    new = [f for f in files if args == ["--all"] or f not in seen]
    results = [digest_one(os.path.join(RINGS, f)) for f in new]

    if results and args != ["--all"]:
        with open(INDEX, "a") as fh:
            for r in results:
                fh.write(json.dumps(r, ensure_ascii=False) + "\n")

    print(f"{'file':>14}  {'bytes':>6}  {'class':<8} {'probe':<5} {'launchd':<7} {'stall':<5} fnv")
    for r in results:
        print(
            f"{r['file']:>14}  {r['bytes']:>6}  {r['class']:<8} "
            f"{r['probe_done']!s:<5} {str(r['launchd_pre']):<7} {str(r['stall']):<5} "
            f"{(r['ex_fnv'] or '')[:14]}"
        )
    if not results:
        print("no new rings")


if __name__ == "__main__":
    main()
