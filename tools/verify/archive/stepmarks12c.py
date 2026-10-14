import pathlib

f = pathlib.Path("/home/placeless/dev/fullerene/fullerene-kernel/src/arch/aarch64/fdt.rs")
s = f.read_text()

# 1) the l/m marks at find_reserved_memory_regions entry
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

# 2) the n mark: the LAST "if walk_result.is_some()" that is followed by the
#    "/// Collect fixed" doc (i.e. the find_reserved_memory_regions return).
marker = "/// Collect fixed"
idx = s.find(marker)
assert idx != -1
# walk back to the "if walk_result.is_some()" of this function's tail
tail = "    if walk_result.is_some() { count } else { 0 }\n}\n\n"
j = s.rfind(tail, 0, idx)
assert j != -1, "tail not found before marker"
insert = "    // Mark n: the structure walk returned.\n    unsafe { super::entry::ane_step_byte(b'n') };\n"
s = s[:j] + insert + s[j:]
f.write_text(s)
print("fdt.rs: l/m/n inserted")
