#!/bin/bash
# The real oeminfo item names, taken from update-binary's own strings.
# update-binary compares SOFTWARE_VER_LIST.mbn against these.
set -u
echo "=== adb -> fastboot ==="
adb reboot bootloader 2>&1
for i in $(seq 1 20); do sleep 2; timeout 10 fastboot devices 2>/dev/null | grep -q . && break; done
timeout 10 fastboot devices 2>&1
echo
run() { printf '%-40s : ' "$1"; timeout 25 fastboot oem oeminforead-"$1" 2>&1 | head -3 | tr '\n' ' '; echo; }

echo "########## the VERLIST items the updater actually reads"
for it in VERLIST OEMSBL_VERLIST AMSS_VERLIST; do run "$it"; done
echo
echo "########## related items guessed from the same string table"
for it in OEMINFO OEMINFO_AMSS_VER_TYPE OEMINFO_OEMSBL_VER_TYPE DEVICE MODEL VENDOR COUNTRY MAIN_VER OEMINFO_OVMODE_STATE; do run "$it"; done
echo
echo "########## back to Android"
timeout 30 fastboot reboot 2>&1
sleep 30
timeout 20 adb devices -l 2>&1
