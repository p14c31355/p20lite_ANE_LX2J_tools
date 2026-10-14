/* Mark probe v2 for the ANE-LX2J: three channels, because one of them was
 * consumed by the boots in between last time.
 *
 * v1 wrote only the pmsg zone, which measurement now suggests is a *mailbox*
 * rather than a log on this device: the 07:21 readback found a single byte in
 * it, and by the next boot both pstore files were gone. The chains that reach a
 * reader here involve intermediate boots (the loader's eRecovery fallback, then
 * Android), so a channel that any boot consumes cannot carry a record across
 * them.
 *
 * v2 writes the same marker into all three ramoops zones, each of which is
 * designed to survive:
 *
 *   WINDOW + 0x60000  console zone  -> console-ramoops-0 (a persistent ring the
 *                                      stock kernel keeps appending to, erased
 *                                      only when read)
 *   WINDOW + 0x00000  dmesg slot 0  -> dmesg-ramoops-0 (a crash-record slot;
 *                                      nothing consumes it until read)
 *   WINDOW + 0xE0000  pmsg zone     -> pmsg-ramoops-0 (kept for completeness)
 *
 * WINDOW is 0x34800000 on the device (`/reserved-memory/pstore-mem`) and is
 * passed with -D for the QEMU self-check, which runs the same instruction
 * sequence against emulated RAM and reads all three records back.
 *
 * Each write is Linux's struct persistent_ram_buffer: sig "DBGC" ^ 0, start 0,
 * data at +12, and size stored last so a reader never sees a size ahead of the
 * bytes it describes.
 */

.equ MARK_SIG, 0x43474244

.section .text, "ax"
.balign 4
.global _start
_start:
    movz w9, #((WINDOW + 0xE0000) >> 16), lsl #16
    movk w9, #((WINDOW + 0xE0000) & 0xffff)
    adr  x12, pmsg_text
    movz w13, #pmsg_len
    bl   .Lzone_write

    movz w9, #(WINDOW >> 16), lsl #16
    movk w9, #(WINDOW & 0xffff)
    adr  x12, dmesg_text
    movz w13, #dmesg_len
    bl   .Lzone_write

    movz w9, #((WINDOW + 0x60000) >> 16), lsl #16
    movk w9, #((WINDOW + 0x60000) & 0xffff)
    adr  x12, console_text
    movz w13, #console_len
    bl   .Lzone_write

.Lhang:
    wfe
    b    .Lhang

/* x9 = zone, x12 = text, w13 = byte count */
.Lzone_write:
    movz w10, #(MARK_SIG & 0xffff)
    movk w10, #(MARK_SIG >> 16), lsl #16
    str  w10, [x9]                      /* sig */
    str  wzr, [x9, #4]                  /* start = 0 */
    add  x11, x9, #12
1:
    ldrb w14, [x12], #1
    strb w14, [x11], #1
    subs w13, w13, #1
    b.ne 1b
    sub  x11, x11, x9
    sub  x11, x11, #12
    str  w11, [x9, #8]                  /* size = written bytes, last */
    ret

.balign 4
pmsg_text:
    .ascii "\n001:E"
.equ pmsg_len, . - pmsg_text
dmesg_text:
    .ascii "====0.000000000\nFULLERENE-ANE-PROBE-DMESG\n"
.equ dmesg_len, . - dmesg_text
console_text:
    .ascii "====0.000000000\nFULLERENE-ANE-PROBE-CONSOLE\n"
.equ console_len, . - console_text
