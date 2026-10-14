import pathlib

f = pathlib.Path("/home/placeless/dev/fullerene/fullerene-kernel/src/arch/aarch64/fdt.rs")
s = f.read_text()

# 1) remove the misplaced n (it went into the previous function)
bad = "    // Mark n: the structure walk returned.\n    unsafe { super::entry::ane_step_byte(b'n') };\n"
assert s.count(bad) == 1, s.count(bad)
s = s.replace(bad, "")

# 2) insert n at the find_reserved_memory_regions tail, right before the final
#    "if walk_result.is_some()" of that function (unique: followed by the
#    Collect-fixed doc comment).
anchor = "    if walk_result.is_some() { count } else { 0 }\n}\n\n/// Collect fixed"
assert s.count(anchor) == 1, s.count(anchor)
s = s.replace(anchor,
    "    // Mark n: the structure walk returned.\n"
    "    unsafe { super::entry::ane_step_byte(b'n') };\n"
    + anchor)
f.write_text(s)

# verify placement: l, m, n all inside find_reserved_memory_regions
lines = s.splitlines()
li = next(i for i, l in enumerate(lines) if "b'l'" in l)
mi = next(i for i, l in enumerate(lines) if "b'm'" in l)
ni = next(i for i, l in enumerate(lines) if "b'n'" in l)
fi = next(i for i, l in enumerate(lines) if "pub fn find_reserved_memory_regions" in l)
print(f"find_reserved at line {fi+1}; l={li+1} m={mi+1} n={ni+1} (all after fn start: {li>fi and mi>fi and ni>fi})")
