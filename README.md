# p20lite_ANE_LX2J_tools

Tools, findings, firmware and screen-console readback for the **Huawei P20 Lite
(ANE-LX2J, Kirin 659 / hi6250, Japan, cust C635)** bring-up of a from-scratch
aarch64 kernel (the fullerene / FullereneOS project).

Everything here was produced by running real experiments on a real device; the
device was unlocked entirely in software (no test-point, no disassembly).

## Start here

- **`docs/ANE_BOOT_CONTRACT.md`** - the boot contract: every measured fact
  about this device, stage by stage. Read this first.
- **`docs/V21_STATE.md`** - the running state log (newest entries at the end).
- **`docs/VERIFICATION_LOOP.md`** - the measurement rules used throughout
  (measure on the real device, verify with primary sources).

## Directory layout

```
docs/       contracts, state log, plans (ANE_BOOT_CONTRACT.md is the key read)
  tmp-notes/    raw working notes, kept for searchability
tools/      everything that drives or processes the phone
  flows/      end-to-end cycles you actually run: ane_arm_and_loop.sh,
              ane_logloop.sh, ane_probe_once.sh, ane_window_flash.sh ...
  probes/     the on-device .S probes that render text to the screen,
              with their .sh assemblers (ane_log_probe.S/.sh is the current one)
  builders/   boot-image construction: mkane_stock_embed.py, mkane_bootimg.py
  diag/       device-state readers (status, identify, pmsg readback, USB monitors)
  analyze/    host-side processing (DT analyzers, package checks, extractors)
  unlock/     the bootloader-unlock era scripts (kept for reference/repro)
  verify/     host verifiers + QEMU proofs (run these before flashing)
artifacts/  bootable images ready to `fastboot flash kernel`
  fullerene-ane-log-probe-stock.img   the current screen reader
  fullerene-ane-*-stock.img           every experimental kernel ever flashed
firmware/   stock firmware and reference data
  kernel_stock.bin      25 MB extracted stock kernel (restores Android)
  ane_dtb/              the device's own DTB (fdt.dtb) + flattened properties
  azrom/                full stock firmware archives (see Firmware below)
logs/       automation logs (usb_runs/) and screen captures from real runs
unlock/     the complete bootloader-unlock record (software-only unlock):
  backup/         the ANE-LX2J_20261002 snapshot: nvme before/after/installed/
                  current, frp_original, misc, oeminfo, the winning exploit
                  binary (cve-2019-2215_working_0x134c838), MD5SUMS + README
  cve-source/     the CVE-2019-2215 exploit source tree (Android.mk + libs)
  device-dumps/   nvme/USRKEY images, oeminfo gamma, fastboot_LK.bin,
                  dts_stock.bin, misc images, before_downgrade.txt
  lk/             the LK disassembly (lk.asm, local-only)
```

## How a cycle runs (the working flow)

1. Get to a fastboot window:
   - cold-off boot that fails lands in a fastboot window after ~2.5-7 minutes
     (exact waits and the LK failure-streak behaviour are in
     `docs/ANE_BOOT_CONTRACT.md`);
   - or `adb reboot bootloader` from Android (no combo needed).
2. Flash the experiment: `fastboot -s <serial> flash kernel artifacts/<img>`.
3. The kernel writes its step-mark record, then parks (early-park vectors stop
   the device falling into eRecovery).
4. After the park a fastboot window opens again; flash the **log probe**
   (`artifacts/fullerene-ane-log-probe-stock.img`) and reboot. The probe
   renders the record + the kernel's durable log as cyan dot-matrix text on
   the screen - readable in one phone photograph.
5. Restore stock: `fastboot flash kernel firmware/kernel_stock.bin` so the
   next boot's failure streak resets and Android comes back.

`tools/flows/ane_logloop.sh` chains all of this automatically
(`bash tools/flows/ane_logloop.sh artifacts/<img>`); `tools/flows/ane_probe_once.sh`
re-enters via adb when Android is already up.

Note: most flows assume the device serial `SCV7N18927000473` is pinned with
`fastboot -s`; adjust for your own unit.

## The screen console (why a photograph works)

The readout channel is the phone display itself:

- The log probe renders 14 rows x 45 columns of 8x8 glyphs (3x scale): the
  last 540 chars of the kernel log plus the 90-char mark record.
- The kernel mirrors every UART byte into a RAM tee; after the MMU is up the
  tee is flushed into the ramoops pmsg zone, and the probe reads it from there.
- The visible budget is ~500 scanlines (approximately 12-14 text rows) before
  the LK's unlock notice area; the renderer is sized to fit.
- Font note: the embedded font (public-domain VGA 8x8, Marcel Sondaar / IBM)
  stores rows LSB-first; the renderer scans MSB-first, so the table is
  bit-reversed at generation time or all glyphs come out mirrored.

## Key findings so far (see docs/ANE_BOOT_CONTRACT.md for the full record)

- The boot proceeds through step marks; the current frontier is the
  **FDT reserved-memory walk** (`find_reserved_memory_regions`) in the
  physical frame allocator (marks l/m/n in the current kernel).
- Reaching the MMU is *flaky* on this device: identical builds sometimes stop
  at mark 9 and sometimes run to mark k. Re-run before concluding.
- The LK keeps a failure-streak counter: the first cold-boot failure opens a
  fastboot window, an immediate second one falls through to eRecovery. A
  successful stock boot resets the streak.
- Reading the screen: any bright phone camera works; a 1920x1080 webcam cannot
  resolve the glyph pitch, and a front-camera photo is fine (the earlier
  "mirrored" readings were the font bug above, not the camera).

## Firmware

`firmware/azrom/` holds stock firmware archives for the ANE family
(Android 8.0 / EMUI 8.0): the KDDI (Japan) build for this exact model, the
C719 open-market builds, and one ANE-TL00 CN build. `firmware/kernel_stock.bin`
is the extracted (and verified by sha256) stock kernel for flashing back.

The same archives are mirrored on archive.org (too large for a git remote):

- Item: https://archive.org/details/p20lite-ane-lx2j-stock-firmware
- Download all of it with:
  ```
  ia download p20lite-ane-lx2j-stock-firmware
  ```
  (or use the "Download Options" on the item page; the `ia` CLI comes from
  `pip install internetarchive` or `uv tool install internetarchive`)

## Safety

- Flashing is limited to the `kernel` partition; the stock kernel is always
  available in `firmware/kernel_stock.bin` and restores the device.
- The tools never touch recovery partitions, configfs, or user data.

## Verification expectations

Before flashing anything new, run the host-side checks:

```
python3 tools/verify/verify_ane_early_vectors.py     # early-park vectors
python3 tools/verify/verify_base_loads.py            # base-load audit
bash    tools/flows/ane_logloop.sh --help 2>/dev/null || true
```

QEMU proofs for the probe assemblers live beside them
(`tools/probes/ane_log_probe.sh` runs a full QEMU render check before it will
package an image).
