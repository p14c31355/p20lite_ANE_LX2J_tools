#!/usr/bin/env python3
"""Make DELAY settable at run time so one build can sweep it.

The race in CVE-2019-2215 is tuned by the DELAY constant, but every rebuild
shifts the effective timing window (the compiled layout changes), so a
compiled-in sweep re-tunes the binary on every step and results are not
comparable. Reading the value from argv keeps the binary fixed and makes the
delay the only thing that varies.

Apply AFTER the compiled-in sweep finishes (it rewrites the header).
Does nothing if already applied.
"""
import re
import sys

SRC = "/home/placeless/dev/p20lite-cve/exploit/cve_2019_2215.c"

src = open(SRC).read()

if "g_delay" in src:
    print("already applied")
    sys.exit(0)

# 1. main() takes argv and parses an optional delay
src = src.replace(
    "int main() {\n    bind_to_core();",
    "unsigned int g_delay = DELAY;\n\n"
    "int main(int argc, char *argv[]) {\n"
    "    if (argc > 1) {\n"
    "        unsigned int d = (unsigned int) strtoul(argv[1], NULL, 0);\n"
    "        if (d > 0) g_delay = d;\n"
    "        printf(\"[>] DELAY overridden to %u us\\n\", g_delay);\n"
    "    }\n"
    "    bind_to_core();",
    1)

# 2. every usleep(DELAY) becomes usleep(g_delay)
src = src.replace("usleep(DELAY)", "usleep(g_delay)")

open(SRC, "w").write(src)

n = src.count("usleep(g_delay)")
ok = "int main(int argc, char *argv[])" in src and "g_delay = DELAY" in src
print(f"usleep sites rewritten: {n}")
print(f"main signature updated: {ok}")
