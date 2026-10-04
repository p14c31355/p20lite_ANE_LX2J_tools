#!/bin/bash
# Sweep the one number that matters, using the range the candidate kernels bracket.
#
# Data points (kernel build date -> avc_cache - fair_sched_class):
#   2018-04-18  0x132e838   (8.0.0.110 C635)
#   2018-06-11  0x134a838   (TL00 8.0.0.151 C01  and  L22J 8.0.0.202 C719)
#   2019-04-25  0x134c838   (8.0.0.127 C719)
#   ?           0x135c838   (exploit's built-in constants - already ruled out by
#                            the pristine runs never escaping u:r:shell:s0)
# The device runs a kernel built 2019-03-01, i.e. between the last two, and the
# difference barely moves over that stretch - so the target is in
# [0x134a838, 0x134c838]. Sweep it densely from the newest end.
set -u
cd /home/placeless/dev/p20-root

echo "############ device present?"
timeout 30 adb devices | tail -2

# build the delta list: start at the newest known value, walk down in 0x100 steps
LIST=$(python3 -c "
v = 0x134c838
out = []
while v >= 0x134a838:
    out.append(f'0x{v:x}')
    v -= 0x100
print(' '.join(out))
")
echo "############ deltas: $LIST"
echo

bash sweep_avc_delta.sh $LIST 2>&1 | tail -60
