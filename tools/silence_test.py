#!/usr/bin/env python3
"""Silence test: wait SILENT seconds (no USB traffic at all), then take ONE
piggyback and check for STG DESK-OK. The hypothesis: the host's own
conversations starve the boot thread's desktop render via the IRQ pump."""
import subprocess
import sys
import time

UV = "/home/placeless/.hermes/bin/uv"
SILENT = int(sys.argv[1]) if len(sys.argv) > 1 else 600


def main():
    print(f"silencing host for {SILENT}s starting {time.strftime('%H:%M:%S')}")
    time.sleep(SILENT)
    print(f"collecting at {time.strftime('%H:%M:%S')}")
    r = subprocess.run(
        [UV, "run", "--with", "pyusb", "--no-project", "python3",
         "piggy_series.py", "3", "rings_night/silence"],
        capture_output=True, text=True, cwd="/home/placeless/dev/p20-root",
        timeout=120,
    )
    print(r.stdout[-400:], r.stderr[-200:])


if __name__ == "__main__":
    main()
