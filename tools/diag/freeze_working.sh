#!/bin/bash
# Freeze the configuration that broke SELinux open, so nothing can lose it.
set -u
cd /home/placeless/dev/p20-root
mkdir -p working
cp /home/placeless/dev/p20lite-cve/libs/arm64-v8a/cve-2019-2215 working/cve-2019-2215_0x134c838
md5sum working/cve-2019-2215_0x134c838
cat > working/README.txt <<'EOF'
Winning configuration (2026-10-02 early morning)

The exploit's effectiveness comes down to ONE number:
    avc_cache - fair_sched_class

  exploit's built-in constants : 0x135c838   -> never escaped u:r:shell:s0
  this build                   : 0x134c838   -> SELinux bypassed, nvme opened

Concrete values used (only the difference matters, but these are what was built):
    FAIR_SCHED_CLASS 0xffffff8008f48408
    AVC_CACHE        0xffffff800a294c40
    DELAY 25

Source of the number: the ANE-LX2J 8.0.0.127(C719) kernel measured at
0x134c838, which matches the device's own kernel (built 2019-03-01) even though
the candidate kernel itself is from 2019-04-25.

Reference measurements (kernel build date -> difference):
    2018-04-18  0x132e838   8.0.0.110(C635)
    2018-06-11  0x134a838   TL00 8.0.0.151(C01), L22J 8.0.0.202(C719)
    2019-04-25  0x134c838   8.0.0.127(C719)  <-- MATCHES THE DEVICE
    ?           0x135c838   exploit's built-in (wrong)
EOF
cat working/README.txt
ls -la working/
echo
echo "=== source state (must show the winning constants) ==="
grep -nE "#define (FAIR_SCHED_CLASS|AVC_CACHE)" /home/placeless/dev/p20lite-cve/exploit/include/kernel_specific.h
grep -nE "^#define DELAY" /home/placeless/dev/p20lite-cve/exploit/include/cve_2019_2215.h
