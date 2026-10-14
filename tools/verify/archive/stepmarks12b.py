import pathlib

f = pathlib.Path("/home/placeless/dev/fullerene/fullerene-kernel/src/arch/aarch64/fdt.rs")
s = f.read_text()

old = """pub fn find_reserved_memory_regions(address: u64, out: &mut [Region]) -> usize {
    let mut states = [ReservedMemoryNodeState::new(); 16];
    let mut count = 0usize;
    let walk_result = walk_structure(address, |event| {"""
new = """pub fn find_reserved_memory_regions(address: u64, out: &mut [Region]) -> usize {
    // Mark l: the reserved-memory walk entry (k->l is the current wall).
    unsafe { super::entry::ane_step_byte(b'l') };
    let mut states = [ReservedMemoryNodeState::new(); 16];
    // Mark m: the 16-slot node-state scratch is up (if the screen stops at m,
    // the walk's visitor frame is what the device cannot survive).
    unsafe { super::entry::ane_step_byte(b'm') };
    let mut count = 0usize;
    let walk_result = walk_structure(address, |event| {"""
assert s.count(old) == 1
s = s.replace(old, new)

old2 = """    });
    if walk_result.is_some() { count } else { 0 }
}

#[derive(Clone, Copy)]"""
new2 = """    });
    // Mark n: the structure walk returned.
    unsafe { super::entry::ane_step_byte(b'n') };
    if walk_result.is_some() { count } else { 0 }
}

#[derive(Clone, Copy)]"""
assert s.count(old2) == 1
s = s.replace(old2, new2)
f.write_text(s)
print("fdt.rs: marks l, m, n inserted")
