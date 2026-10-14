import pathlib

f = pathlib.Path("/home/placeless/dev/fullerene/fullerene-kernel/src/arch/aarch64/fdt.rs")
s = f.read_text()

bad = "    // Mark n: the structure walk returned.\n    unsafe { super::entry::ane_step_byte(b'n') };\n"
assert s.count(bad) == 1
s = s.replace(bad, "")

anchor = "    });\n    if walk_result.is_some() { count } else { 0 }\n}\n\n#[derive(Clone, Copy)]\nstruct StructureProperty"
assert s.count(anchor) == 1, s.count(anchor)
s = s.replace(anchor,
    "    });\n    // Mark n: the structure walk returned.\n"
    "    unsafe { super::entry::ane_step_byte(b'n') };\n"
    "    if walk_result.is_some() { count } else { 0 }\n}\n\n#[derive(Clone, Copy)]\nstruct StructureProperty")
f.write_text(s)

lines = s.splitlines()
fi = next(i for i, l in enumerate(lines) if "pub fn find_reserved_memory_regions" in l)
li = next(i for i, l in enumerate(lines) if "b'l'" in l)
mi = next(i for i, l in enumerate(lines) if "b'm'" in l)
ni = next(i for i, l in enumerate(lines) if "b'n'" in l)
print(f"find_reserved line {fi+1}; l={li+1} m={mi+1} n={ni+1}; ordered: {fi<li<mi<ni}")
