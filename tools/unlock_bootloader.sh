#!/bin/bash
# The documented unlock, via hisi-nve's own README procedure:
#   1. write USRKEY = sha256(our chosen unlock code)
#   2. reboot to the bootloader
#   3. fastboot oem unlock <that code>   -> the bootloader verifies against USRKEY
#
# FBLOCK=0 alone did not move the bootloader's state, which fits: FBLOCK is the
# flag the unlock procedure is meant to clear, and the gate in front of it is the
# USRKEY check that "check password failed" was complaining about.
#
# The unlock wipes userdata - expected and acceptable.
set -u
cd /home/placeless/dev/p20-root
CODE=0123456789ABCDEF
NVME=/dev/block/bootdevice/by-name/nvme

echo "############ 0. back to Android"
timeout 60 fastboot reboot 2>&1 | head -2
sleep 30
for i in $(seq 1 30); do
  ST=$(timeout 20 adb devices 2>/dev/null | awk 'NR==2{print $2}')
  echo "  adb: ${ST:-none}"
  [ "$ST" = "device" ] && break
  sleep 10
done

echo
echo "############ 1. did the FBLOCK=0 survive the reboot?"
timeout 300 adb shell /data/local/tmp/cve-2019-2215 <<'EOF' 2>&1 | grep -aE "FBLOCK [0-9]|wrote|Successfully|context=|uid=0" | head -12
id
cat /proc/self/attr/current
/data/local/tmp/hisi-nve r FBLOCK
exit
EOF

echo
echo "############ 2. write our unlock code into USRKEY (tool hashes it for hi6250)"
timeout 300 adb shell /data/local/tmp/cve-2019-2215 <<EOF 2>&1 | grep -aiE "USRKEY|Successfully|error|fail" | head -8
/data/local/tmp/hisi-nve w USRKEY $CODE
/data/local/tmp/hisi-nve r USRKEY
exit
EOF

echo
echo "############ 3. to the bootloader and unlock"
timeout 60 adb reboot bootloader 2>&1
sleep 25
for i in $(seq 1 20); do sleep 2; timeout 10 fastboot devices 2>/dev/null | grep -q . && break; done
timeout 20 fastboot devices 2>&1 | head -2

echo "--- unlock with the code we just installed:"
timeout 120 fastboot oem unlock $CODE 2>&1 | head -10
sleep 20

echo
echo "############ 4. the verdict"
for i in $(seq 1 20); do sleep 2; timeout 10 fastboot devices 2>/dev/null | grep -q . && break; done
timeout 60 fastboot oem lock-state info 2>&1 | head -6
timeout 60 fastboot oem get-bootinfo 2>&1 | head -4
