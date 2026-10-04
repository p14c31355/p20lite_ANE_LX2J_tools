#!/usr/bin/env python3
"""Decode the stamp probe's 8-run stamp from a webcam frame.

The stamp layout (each run = 256 KiB = ~60 panel rows):
  runs 0..3 = the candidate index in binary (white = 1, black = 0)
  runs 4..7 = white green blue yellow (marker tail)
Row profile: classify each row of the screen strip, collapse into runs
(short runs absorbed), then look for a binary prefix followed by the
marker tail. The raw RGB of every run is printed so the reading can be
eyeballed when the auto-classifier is unsure under dim light.

NOTE: the marks-probe bands (white green blue yellow cyan magenta red
orange, one per step mark) also appear via this profile - for those, count
the runs, not the index decode.

Usage: ane_stamp_read.py FRAME [FRAME...]
"""
import sys
from PIL import Image

PAL = {"green": (0, 255, 0), "blue": (0, 0, 255), "yellow": (255, 255, 0),
       "cyan": (0, 255, 255), "magenta": (255, 0, 255), "red": (255, 0, 0),
       "orange": (255, 128, 0)}


def classify(rgb):
    r, g, b = rgb
    mx, mn = max(rgb), min(rgb)
    if mx < 25:
        return "black"
    if mx - mn < 30:
        return "white"
    v = mx or 1
    best, bd = None, 1e9
    for name, pal in PAL.items():
        pv = max(pal) or 1
        d = sum((rgb[i] / v - pal[i] / pv) ** 2 for i in range(3))
        if d < bd:
            bd, best = d, name
    return best


def row_runs(im, x0f=0.20, x1f=0.72, y0=60, y1=300, step=2, min_rows=5):
    w, h = im.size
    rows = []
    for y in range(y0, y1, step):
        px = [im.getpixel((x, y)) for x in range(int(w * x0f), int(w * x1f))]
        n = len(px)
        rgb = (sum(p[0] for p in px) / n, sum(p[1] for p in px) / n,
               sum(p[2] for p in px) / n)
        rows.append((y, rgb, classify(rgb)))
    runs = []
    cur, start, acc = None, None, []
    for y, rgb, name in rows:
        if name != cur:
            if cur is not None:
                runs.append([cur, start, y, acc])
            cur, start, acc = name, y, [rgb]
        else:
            acc.append(rgb)
    runs.append([cur, start, rows[-1][0], acc])
    # absorb runs shorter than min_rows into the previous run
    merged = []
    for r in runs:
        if merged and (r[2] - r[1]) < min_rows:
            merged[-1][2] = r[2]
        else:
            merged.append(r)
    return merged


def decode(path):
    im = Image.open(path).convert("RGB")
    runs = row_runs(im)
    print(f"== {path}")
    for name, a, b, acc in runs:
        n = len(acc)
        r = sum(p[0] for p in acc) / n
        g = sum(p[1] for p in acc) / n
        bl = sum(p[2] for p in acc) / n
        print(f"   {name:8s} y{a:3d}-{b:3d} ({b-a:2d} rows) rgb=({r:4.0f},{g:4.0f},{bl:4.0f})")
    names = [r[0] for r in runs]
    found = False
    for i in range(len(names) - 7):
        win = names[i:i + 8]
        if win[4:] == ["white", "green", "blue", "yellow"] and \
           all(x in ("white", "black") for x in win[:4]):
            idx = sum(1 << j for j, x in enumerate(win[:4]) if x == "white")
            print(f"   DECODED index {idx} (bits {win[:4]}) at run {i}")
            found = True
    if not found:
        for i in range(len(names) - 3):
            w4 = names[i:i + 4]
            if all(x in ("white", "black") for x in w4) and "white" in w4:
                idx = sum(1 << j for j, x in enumerate(w4) if x == "white")
                print(f"   possible index {idx} (prefix {w4}) at run {i}; marker tail not seen")
    return runs


if __name__ == "__main__":
    for p in sys.argv[1:]:
        decode(p)
        print()
