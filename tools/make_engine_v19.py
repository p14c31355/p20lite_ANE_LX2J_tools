#!/usr/bin/env python3
"""v19 engine transform: night_engine_v18.sh -> night_engine_v19.sh

An engine restart silently missed the boot already in flight: EV was
initialised to the last attach line, so the loop never saw it as a new
event (boot #27 was lost this way right after the v18 swap). Starting
with an EMPTY baseline makes the first loop iteration process the
attach that is already on the bus.
"""

src = open("night_engine_v18.sh").read()

old = '''EV="$(last_event)"'''
new = '''# v19: start with an EMPTY baseline so the first loop iteration treats the
# attach already on the bus as a fresh event. v18 started with the last
# attach as EV and silently missed the boot that was in flight at restart
# (boot #27). A stale/dead attach processed this way simply fails its
# settle+CNXN and the loop moves on.
EV=""'''
assert old in src, "EV= init not found"
src = src.replace(old, new, 1)
src = src.replace("night engine v18 start", "night engine v19 start")
src = src.replace("night engine v18 done", "night engine v19 done")

open("night_engine_v19.sh", "w").write(src)
print("night_engine_v19.sh written,", len(src), "chars")
