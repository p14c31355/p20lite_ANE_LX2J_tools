ANE-LX2J (Huawei P20 Lite, C635, 8.0.0.151) - bootloader unlock, 2026-10-02
==========================================================================

Result: bootloader unlocked via software only (no test points, no paid tools).
The device now reports the unlocked state to the bootloader and accepts
fastboot commands.

The unlock code that was installed:  0123456789ABCDEF
(SHA256 of it was written into the nvme partition's USRKEY property.)


WHAT EACH FILE IS
-----------------

nvme_BEFORE_FBLOCK_write.bin
    The nvme partition as it was before we wrote anything: all seven FBLOCK
    copies still read 1 (locked), USRKEY still held the factory value.
    This is the "undo everything" reference.

nvme_after_FBLOCK0.bin
    Same partition after FBLOCK was cleared. Seven FBLOCK copies read 0.

nvme_usrkey_installed.bin
    The image actually written back to the device: FBLOCK=0 plus
    SHA256("0123456789ABCDEF") in all seven USRKEY value fields.
    This is the state the device is in now.

frp_original.bin
    The frp partition, untouched. Layout: the first 32 bytes are
    SHA256(rest of the partition with those bytes zeroed); at 0x20 sits the
    AOSP persistent-data-block magic 0x73189019. We never modified it.

misc.bin, oeminfo.bin
    Bootloader control block and device identity, as they were.

cve-2019-2215_working_0x134c838
    The exploit build that defeated SELinux on this device. The number in the
    name is avc_cache - fair_sched_class, which is the only thing the exploit
    really needs to get right:
        kernel 8.0.0.151 (this device)      -> 0x134c838
        exploit's built-in value            -> 0x135c838 (wrong, never worked)
    Constants in it: FAIR_SCHED_CLASS 0xffffff8008f48408,
    AVC_CACHE 0xffffff800a294c40, DELAY 25.

exploit_README.txt
    How that build was produced and what was measured.

kernel_8.0.0.110.elf
    Reconstructed kernel with symbols, used to derive the constants.
    (8.0.0.110 is a different build from the device's 8.0.0.151 - its
    fair_sched_class/avc_cache do not apply, but it anchors the measurement.)

liboeminfo_from_device.so
    Huawei's oeminfo library, pulled for reference while investigating the
    OEM-unlock toggle.


HOW TO RESTORE, IF EVER NEEDED
-------------------------------

The nvme partition is /dev/block/mmcblk0p7 (by-name/nvme), 6,291,456 bytes.
From a root shell on the device:

    dd if=<image> of=/dev/block/bootdevice/by-name/nvme bs=4096
    sync

Use nvme_usrkey_installed.bin to return to the unlocked state, or
nvme_BEFORE_FBLOCK_write.bin to put everything back to factory.
Verify afterwards with:  fastboot oem lock-state info


HOW ROOT WAS OBTAINED (summary)
-------------------------------
CVE-2019-2215 against the binder driver; the exploit needs the value
avc_cache - fair_sched_class of the running kernel to bypass SELinux.
Measured across four firmware packages obtained from azrom, the device's
kernel (built 2019-03-01) matches the 8.0.0.127(C719) kernel's layout
(0x134c838). With that value the exploit escapes u:r:shell:s0 and can open
block devices. Full details: see the skill reference ane-lx2j.md.
