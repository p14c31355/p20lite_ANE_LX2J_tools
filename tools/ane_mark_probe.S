/* Tiny L0 probe for the ANE-LX2J.
 *
 * Deliberately not Fullerene: no MMU, no stack, no relocations, no BSS, no C.
 * It answers exactly one question - did the loader place this image at its
 * kernel address and enter its first instruction - and answers it through the
 * one channel that survives a power cycle on this board: the ramoops pmsg zone,
 * which a later boot can read back with root.
 *
 * MARK_BASE is that zone: 0x34800000 + 0xE0000, from the device's own device
 * tree (`/ramoops`: record-size 0x20000 x3, console-size 0x80000,
 * pmsg-size 0x20000). Pass -D on the assembler command line to retarget it
 * (the QEMU self-check points it at emulated RAM).
 *
 * The 18 bytes written are exactly what fullerene-kernel/src/blackbox.rs writes
 * for its first record of a boot, so the same reader parses both:
 *
 *   +0x00  sig   = 0x43474244  ("DBGC" ^ 0, Linux's persistent_ram_buffer)
 *   +0x04  start = 0
 *   +0x08  size  = 6
 *   +0x0c  data  = "\n001:E"   (segment marker, ordinal 1, CODE_ANE_ENTRY)
 *
 * size is stored last so a reader arriving mid-write never sees a size ahead of
 * the data. Then it halts: a dark screen with a live bus is itself a result, and
 * the record is read after the next power cycle.
 */

.equ MARK_SIG, 0x43474244

.section .text, "ax"
.balign 4
.global _start
_start:
    movz w9, #(MARK_BASE >> 16), lsl #16
    movk w9, #(MARK_BASE & 0xffff)      /* w9 = MARK_BASE: the pmsg zone */

    movz w10, #(MARK_SIG & 0xffff)
    movk w10, #(MARK_SIG >> 16), lsl #16
    str  w10, [x9]                      /* sig */
    str  wzr, [x9, #4]                  /* start = 0 */

    movz w11, #0x0a                     /* '\n' */
    strb w11, [x9, #12]
    movz w11, #0x30                     /* '0' */
    strb w11, [x9, #13]
    strb w11, [x9, #14]
    movz w11, #0x31                     /* '1' */
    strb w11, [x9, #15]
    movz w11, #0x3a                     /* ':' */
    strb w11, [x9, #16]
    movz w11, #0x45                     /* 'E' (CODE_ANE_ENTRY) */
    strb w11, [x9, #17]

    movz w10, #6
    str  w10, [x9, #8]                  /* size = 6, last */

.Lhang:
    wfe
    b .Lhang
