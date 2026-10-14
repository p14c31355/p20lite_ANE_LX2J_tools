#!/usr/bin/env python3
print("v319 plan: usb_reenumerate waits for EP1 quiet (no conversation for")
print("10 s) up to 60 s total, then either does the D+ cycle (quiet core)")
print("or skips it (conversation never ended). This defuses the mid-")
print("conversation DCTL write stall measured at +35 s (STG PRE-RENUM was")
print("the last ring event before the park).")
