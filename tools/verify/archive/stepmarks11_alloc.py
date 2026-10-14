import pathlib

# allocator.rs: bisect the h->q span with f/g/i/j/k/l/m/n
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
print("allocator.rs: f/g/i/j/k/l/m/n inserted")
