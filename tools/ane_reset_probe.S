/* Reset probe for the ANE-LX2J: the smallest possible "did the loader enter our
 * code" question.
 *
 * The v2 probe wrote records into three ramoops zones and nothing appeared, but
 * that result conflates two causes: the loader may never have entered the
 * payload, or it entered it in a state where those stores do not land (an
 * enabled MMU whose tables do not cover the reserved window). This probe
 * removes memory from the question entirely: it calls PSCI SYSTEM_RESET, a
 * single SMC, and touches no memory at all.
 *
 * Outcome, read off the screen:
 *   reboot loop (logo repeating) -> the loader entered our code at the kernel
 *                                   address and the SMC conduit reaches EL3.
 *   nothing at all               -> the loader did not enter us (or trapped the
 *                                   SMC); the loading contract is the problem,
 *                                   not the payload's stores.
 *
 * The kernel is still flashed in the kernel partition, so each reset boots this
 * payload again - the loop is the signal. The user stops it with Volume Down +
 * Power into fastboot, and the stock kernel is restored from there.
 *
 * PSCI: function ID 0x84000009 (SYSTEM_RESET, PSCI 0.2+), x1..x3 zero.
 */

.section .text, "ax"
.balign 4
.global _start
_start:
    movz w0, #0x0009
    movk w0, #0x8400, lsl #16       /* x0 = 0x84000009 SYSTEM_RESET */
    mov  x1, xzr
    mov  x2, xzr
    mov  x3, xzr
    smc  #0

.Lhang:                             /* if the SMC never resets, sit here */
    wfe
    b    .Lhang
