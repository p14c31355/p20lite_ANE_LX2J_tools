/* The liveness probe - the smallest possible payload.
 *
 * Three device runs of the full bring-up probes (l1d on 10-03, l1d2/l1d3
 * tonight) have left no readable trace: the target zone still reads as the
 * park's 0xAA fill. Either the loader never jumps into a payload built this
 * way, or the code dies before its first trace write. This payload decides
 * between those: it touches no hardware at all. It stores a marker in
 * slot 1 and then a climbing counter in slot 2 of the v8b read window.
 *
 * If the marker reads back after a run, the loader does enter our code and
 * the counter's final value is how long the payload ran before the loader's
 * fallback took the machine away.
 *
 * Slot - the v8b reads [LIVE_BASE + 0] as the step word and [+4] as the
 * value word for entry 1, so the marker lands in the value half.
 */
    .set LIVE_BASE, 0x348DF100

    .text
    .global _start
_start:
    movz x15, #((LIVE_BASE) >> 16), lsl #16
    movk x15, #((LIVE_BASE) & 0xffff)
    movz w10, #0x494C                  /* bytes 4C 49 = "LI" */
    movk w10, #0x4546, lsl #16         /* bytes 46 45 = "FE" -> "LIFE" */
    str  w10, [x15, #0x04]             /* entry 1 value: the marker */
    mov  w11, #0
1:  str  w11, [x15, #0x0C]             /* entry 2 value: the counter */
    add  w11, w11, #1
    movz w12, #0x4000
2:  subs w12, w12, #1
    b.ne 2b
    b    1b
