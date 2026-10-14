#!/usr/bin/env python3
"""nohost_test.py - verify the park is conditional on host conversation.

Drive: flash v313, let it boot WITHOUT any host conversation, and watch the
journal for a disconnect (the reenumerate D+ drop/raise = a fresh
enumeration ~30-60 s after the first attach). If the reenumerate completes
with no host talking, the boot reaches the desktop and the journal shows a
second enumeration cycle. If it parks, no second enumeration ever appears.
"""
import subprocess
import sys
import time


def journal_tail(minutes):
    out = subprocess.run(
        ["journalctl", "-k", "--since", f"-{minutes} min", "--no-pager", "-o", "short-iso"],
        capture_output=True, text=True,
    ).stdout
    return out


def main():
    watch_s = int(sys.argv[1]) if len(sys.argv) > 1 else 300
    t0 = time.time()
    events = []
    while time.time() - t0 < watch_s:
        out = journal_tail(1)
        for line in out.splitlines():
            if "Product: ANE fastboot" in line:
                events.append(("ATTACH", line[:19]))
            elif "Product: Fastboot2.0" in line:
                events.append(("LOADER", line[:19]))
            elif "USB disconnect" in line:
                events.append(("DISCONN", line[:19]))
        # dedupe consecutive
        dedup = []
        for e in events:
            if not dedup or dedup[-1] != e:
                dedup.append(e)
        events = dedup
        time.sleep(5)
    for e in events:
        print(*e)
    # Analysis: attach -> disconnect -> attach = reenumerate completed.
    attaches = [e for e in events if e[0] == "ATTACH"]
    print(f"\nattach count in {watch_s}s: {len(attaches)}")
    if len(attaches) >= 2:
        print("REENUMERATE COMPLETED (no host conversation) -> desktop reachable")
    elif len(attaches) == 1:
        print("NO second enumeration -> boot parked at reenumerate (or died)")
    else:
        print("no attach observed in the window")


if __name__ == "__main__":
    main()
