#!/usr/bin/env python3
"""Split the fullerene-ane-fastboot skill: move the eMMC/SDHCI section to
references/emmc-sdhci.md so SKILL.md fits under the 100k limit."""
import os
import re

skill_dir = os.path.expanduser("~/.hermes/skills/kernel-development/fullerene-ane-fastboot")
skill_md = os.path.join(skill_dir, "SKILL.md")
refs_dir = os.path.join(skill_dir, "references")
os.makedirs(refs_dir, exist_ok=True)

src = open(skill_md).read()
print("before:", len(src), "chars")

start_marker = "## eMMC (Arasan SDHCI @0xFF390000)"
i0 = src.find(start_marker)
assert i0 > 0, "eMMC section not found"
# next top-level "## " after i0:
m = re.search(r"\n## ", src[i0 + 10:])
assert m, "next section not found"
i1 = i0 + 10 + m.start() + 1  # start of the next "\n## " -> position of "\n"

section = src[i0:i1]
pointer = (
    "## eMMC (Arasan SDHCI @0xFF390000) - the real internal storage\n\n"
    "Full bring-up detail moved to `references/emmc-sdhci.md` (2026-10-07,\n"
    "skill size). It covers: the controller identity/reset/clock recipe, the\n"
    "genome/ext4 layout (GPT56P, EX_LBA, FNV, UD_LBA), EmmcBlockDevice +\n"
    "mount, the 512KB->8MB->32MB heap history, speed notes (400 kHz), the\n"
    "kernel LBA (901120), and every command/register constant learned.\n\n"
)

ref = (
    "# eMMC (Arasan SDHCI @0xFF390000) - full detail (moved from SKILL.md)\n\n"
    + section.split("\n", 1)[1]
)
open(os.path.join(refs_dir, "emmc-sdhci.md"), "w").write(ref)

new = src[:i0] + pointer + src[i1:]
open(skill_md, "w").write(new)
print("after:", len(new), "chars; reference:", len(ref), "chars")
