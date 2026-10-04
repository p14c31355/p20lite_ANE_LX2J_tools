import pathlib

# 1) entry.rs: retire marks 2-5 (keep 1 as the earliest sanity)
p = pathlib.Path("/home/placeless/dev/fullerene/fullerene-kernel/src/arch/aarch64/entry.rs")
s = p.read_text()
for mark in ["2", "3", "4", "5"]:
    old = f"    unsafe {{ ane_step_byte(b'{mark}') }};\n"
    assert s.count(old) == 1, (mark, s.count(old))
    s = s.replace(old, "")
p.write_text(s)
print("entry.rs: marks 2-5 retired")

# 2) main.rs: retire marks 6/7/8 (keep 9, b, c, d, e, a)
q = pathlib.Path("/home/placeless/dev/fullerene/fullerene-kernel/src/arch/aarch64/main.rs")
t = q.read_text()
for mark in ["6", "7", "8"]:
    old = f"    unsafe {{ entry::ane_step_byte(b'{mark}') }};\n"
    assert t.count(old) == 1, (mark, t.count(old))
    t = t.replace(old, "")
q.write_text(t)
print("main.rs: marks 6-8 retired")

# 3) allocator.rs: bisect the h->q span with f/g/i/j/k/l/m/n
a = pathlib.Path("/home/placeless/dev/fullerene/fullerene-kernel/src/arch/aarch64/allocator.rs")
u = a.read_text()
def rep(old, new, n=1):
    global u
    c = u.count(old)
    assert c == n, f"count {c} != {n}: {old[:60]!r}"
    u = u.replace(old, new)

rep("""        trace("alloc: enter\\n");
        let count = (info.memory_map_size as usize)
            .checked_div(core::mem::size_of::<fdt::Region>())?
            .min(MAX_FRAME_RANGES);
        trace("alloc: count ok\\n");""",
    """        trace("alloc: enter\\n");
        unsafe { super::entry::ane_step_byte(b'f') };
        let count = (info.memory_map_size as usize)
            .checked_div(core::mem::size_of::<fdt::Region>())?
            .min(MAX_FRAME_RANGES);
        trace("alloc: count ok\\n");
        unsafe { super::entry::ane_step_byte(b'g') };""")

rep("""        trace("alloc: slice ok\\n");
                trace("alloc: q mark\\n");""",
    """        trace("alloc: slice ok\\n");
        unsafe { super::entry::ane_step_byte(b'i') };""")

rep("""            shared: [SharedFrame::EMPTY; MAX_SHARED_FRAMES],
        };
        // Mark r (h2): the ~27 KiB allocator object finished initialising in
        // its stack slot (NRVO target); this is where a stack shortfall on
        // the device would first clobber the frame.
""",
    """            shared: [SharedFrame::EMPTY; MAX_SHARED_FRAMES],
        };
        unsafe { super::entry::ane_step_byte(b'j') };
""")

rep("""        ));
        // Mark s (h3): the four linker-symbol reservations are in place.
        if info.fdt_address != 0 {""",
    """        ));
        unsafe { super::entry::ane_step_byte(b'k') };
        if info.fdt_address != 0 {""")

rep("""        }
        // Mark t (h4): the reserved-memory walk and its push loop returned.
        if let Some(header) = fdt::inspect(info.fdt_address) {""",
    """        }
        unsafe { super::entry::ane_step_byte(b'l') };
        if let Some(header) = fdt::inspect(info.fdt_address) {""")

rep("""        }

        for region in regions {""",
    """        }
        unsafe { super::entry::ane_step_byte(b'm') };

        for region in regions {""")

rep("""            .unwrap_or(0);
        // Mark i: the allocator object is fully built; the return and the
        // caller's binding are all that remain.
        Some(allocator)""",
    """            .unwrap_or(0);
        unsafe { super::entry::ane_step_byte(b'n') };
        Some(allocator)""")

a.write_text(u)
import subprocess
print(subprocess.run(["grep","-n","ane_step_byte","fullerene-kernel/src/arch/aarch64/allocator.rs"],capture_output=True,text=True).stdout)
