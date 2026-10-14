#!/usr/bin/env python3
"""v319 shims: route the reenumerate quiet-wait's conversations_served()
read through a crate-root function so the host test include compiles."""
import pathlib

# 1. remove the ane_usb_dev include from the test file, add a stub
p = pathlib.Path('/home/placeless/dev/fullerene/fullerene-kernel/tests/ane_mmio_ranges.rs')
s = p.read_text()
s = s.replace('''#[path = "../src/platform/ane/ane_usb_dev.rs"]
mod ane_usb_dev;

''', '')
if 'conversations_served' not in s:
    s = s.replace('''pub(crate) fn ane_tick_count() -> u32 {
    0
}''', '''pub(crate) fn ane_tick_count() -> u32 {
    0
}

pub(crate) fn conversations_served() -> u32 {
    0
}''')
p.write_text(s)
print('test file stubbed')

# 2. ane/mod.rs: route through crate::ane_conversations()
p2 = pathlib.Path('/home/placeless/dev/fullerene/fullerene-kernel/src/platform/ane/mod.rs')
s2 = p2.read_text()
s2 = s2.replace('super::ane_usb_dev::conversations_served()', 'crate::ane_conversations()')
p2.write_text(s2)
print('ane/mod.rs routed')

# 3. bin.rs (the aarch64 kernel crate root)
p3 = pathlib.Path('/home/placeless/dev/fullerene/fullerene-kernel/src/arch/aarch64/bin.rs')
s3 = p3.read_text()
if 'ane_conversations' not in s3:
    s3 += '''
// v319: the reenumerate quiet-wait reads the EP1 conversation counter
// through the crate root (ane_usb_dev is a platform-level sibling).
pub(crate) fn ane_conversations() -> u32 {
    runtime::platform::ane_usb_dev::conversations_served()
}
'''
    p3.write_text(s3)
print('bin.rs shimmed')

# 4. main.rs (the x86 root) - stub (the ane platform never compiles there)
p4 = pathlib.Path('/home/placeless/dev/fullerene/fullerene-kernel/src/main.rs')
s4 = p4.read_text()
if 'ane_conversations' not in s4:
    s4 = s4.replace('''pub(crate) fn ane_tick_count() -> u32 {
    aarch64_runtime::exceptions::tick_count()
}''', '''pub(crate) fn ane_tick_count() -> u32 {
    aarch64_runtime::exceptions::tick_count()
}

#[cfg(target_arch = "aarch64")]
pub(crate) fn ane_conversations() -> u32 {
    aarch64_runtime::platform::ane_usb_dev::conversations_served()
}''')
    p4.write_text(s4)
print('main.rs shimmed')
