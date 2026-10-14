/* The liveness probe v2 - stock-sized packaging + arm-watchdog feed.
 *
 * The 4KB probes (l1d/l1d2/l1d3/live) never left a trace; the 11.6MB
 * stock-embedded images (v8b) boot and render every time. This payload is
 * packaged the v8b way (embedded at the stock kernel's 0x1660000) and adds
 * the SP805 feed from l1d3's hold so the loader's fallback never runs - the
 * trace stays readable until a manual combo.
 *
 * Writes: entry-1 value "LIFE", entry-2 value = a counter stepping once per
 * feed cycle (~7ms), and the watchdog kicked every cycle. */
    .set LIVE_BASE, 0x348DF100
    .set WDOG_BASE, 0xe8a06000

    .text
    .global _start
_start:
    movz x15, #((LIVE_BASE) >> 16), lsl #16
    movk x15, #((LIVE_BASE) & 0xffff)
    movz w10, #0x494C                  /* bytes 4C 49 = "LI" */
    movk w10, #0x4546, lsl #16         /* bytes 46 45 = "FE" -> "LIFE" */
    str  w10, [x15, #0x04]             /* entry 1 value: the marker */

    movz x13, #((WDOG_BASE) >> 16), lsl #16
    movk x13, #((WDOG_BASE) & 0xffff)
    movz w11, #0xCE55
    movk w11, #0x1ACC, lsl #16
    str  w11, [x13, #0xC00]            /* unlock 0x1ACCE551 */

    mov  w11, #0                       /* the lifetime counter */
1:  str  w11, [x15, #0x0C]             /* entry 2 value: the counter */
    add  w11, w11, #1
    movz w12, #0x4000
    movk w12, #0x40, lsl #16           /* ~4M iterations -> ~7ms/cycle */
2:  subs w12, w12, #1
    b.ne 2b
    mov  w12, #1
    str  w12, [x13, #0x0C]             /* kick the arm watchdog */
    b    1b
