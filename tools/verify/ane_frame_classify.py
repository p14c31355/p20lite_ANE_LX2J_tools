#!/usr/bin/env python3
"""Classify the night's camera frames: paint bands vs unlock warning vs dark.

The paint probe draws full-width horizontal colour bands (its palette is
white, green, blue, yellow, cyan, magenta, red, orange for band 0 upward).
The unlock warning splash is an organic Huawei graphic (blue/gold, mixed per
row, not full-width uniform).  Dark/EMUI screens are neither.

So the discriminator is per-row uniformity: for every row, count saturated
pixels and their colour spread.  A band row is overwhelmingly saturated with
a tight colour spread; a warning-graphic row is partly saturated with a wide
spread.  Runs of consecutive band rows = the bands, and their mean colours
name them.

Usage: ane_frame_classify.py <cam_dir|jpg...> [--json out.json]
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

PALETTE = [
    ("white", (255, 255, 255)),
    ("green", (0, 255, 0)),
    ("blue", (0, 0, 255)),
    ("yellow", (255, 255, 0)),
    ("cyan", (0, 255, 255)),
    ("magenta", (255, 0, 255)),
    ("red", (255, 0, 0)),
    ("orange", (255, 165, 0)),
]


def load_rgb(path):
    im = Image.open(path).convert("RGB")
    # small enough for row statistics; keep aspect
    im.thumbnail((320, 320))
    return np.asarray(im, dtype=np.float32) / 255.0


def row_stats(rgb):
    """Per-row: saturated fraction, mean colour of saturated pixels, spread."""
    mx = rgb.max(axis=2)
    mn = rgb.min(axis=2)
    sat = (mx - mn)  # 0..1 chroma proxy
    satmask = (sat > 0.25) & (mx > 0.2)
    frac = satmask.mean(axis=1)
    rows = []
    for y in range(rgb.shape[0]):
        m = satmask[y]
        if m.sum() >= 4:
            cols = rgb[y][m]
            mean = cols.mean(axis=0)
            spread = float(np.abs(cols - mean).mean())
        else:
            mean = np.zeros(3)
            spread = 0.0
        rows.append((float(frac[y]), mean, spread))
    return rows


def classify(path):
    rgb = load_rgb(path)
    lum = float(rgb.mean())
    rows = row_stats(rgb)

    band_rows = [i for i, (f, _, sp) in enumerate(rows) if f > 0.55 and sp < 0.18]
    warn_rows = [i for i, (f, _, sp) in enumerate(rows) if f > 0.15 and sp >= 0.18]

    # group band rows into consecutive runs
    bands = []
    for i in band_rows:
        if bands and i == bands[-1][-1] + 1:
            bands[-1].append(i)
        else:
            bands.append([i])

    named = []
    for run in bands:
        if len(run) < 2:
            continue
        mean = np.mean([rows[y][1] for y in run], axis=0)
        name, dist = "?", 9.9
        for n, ref in PALETTE:
            d = float(np.abs(mean - np.array(ref) / 255.0).mean())
            if d < dist:
                name, dist = n, d
        named.append({"rows": [run[0], run[-1]], "height": len(run),
                      "rgb": [round(float(c) * 255) for c in mean],
                      "palette": name, "dist": round(dist, 3)})

    if len(named) >= 2:
        kind = "bands"
    elif len(warn_rows) > rgb.shape[0] * 0.15:
        kind = "warning-or-organic"
    elif lum < 0.06:
        kind = "dark"
    else:
        kind = "other"

    return {
        "file": Path(path).name,
        "kind": kind,
        "luminance": round(lum, 3),
        "band_count": len(named),
        "bands": named,
    }


def main():
    args = []
    skip = False
    for i, a in enumerate(sys.argv[1:]):
        if skip:
            skip = False
            continue
        if a == "--json":
            skip = True
            continue
        if not a.startswith("--"):
            args.append(a)
    out_json = None
    if "--json" in sys.argv:
        out_json = sys.argv[sys.argv.index("--json") + 1]
    files = []
    for a in args:
        p = Path(a)
        if p.is_dir():
            files.extend(sorted(p.glob("*.jpg")))
        else:
            files.append(p)
    results = []
    for f in files:
        try:
            r = classify(f)
        except Exception as e:  # noqa: BLE001 - report, never crash the batch
            r = {"file": Path(f).name, "kind": f"error:{e}"}
        results.append(r)
        bands = r.get("bands", [])
        desc = ", ".join(f"{b['palette']}(h{b['height']})" for b in bands[:14])
        print(f"{r['file']:>20}  {r['kind']:<18} lum={r.get('luminance','-')} "
              f"bands={r.get('band_count','-')}  {desc}")
    if out_json:
        Path(out_json).write_text(json.dumps(results, indent=2))
        print(f"\nwrote {out_json}")
    kinds = {}
    for r in results:
        kinds[r["kind"]] = kinds.get(r["kind"], 0) + 1
    print("\nsummary:", kinds)


if __name__ == "__main__":
    main()
