# p20lite_ANE_LX2J_tools

A toolkit for the **bootloader unlock (BLU)** of the **Huawei P20 Lite
(ANE-LX2J, Kirin 659 / hi6250, Japan cust C635)** and for **porting
alternative operating systems** to the device: custom ROMs, mainline
Linux-based kernels, homebrew OS projects. The unlock procedure and the boot
contract are documented OS-independently; everything recorded here was
measured on real hardware. The device was unlocked **entirely in software** —
no disassembly, no test points, no paid unlock services.

> [日本語版はこちら](README.ja.md)

## What this repository gives you

1. **A bootloader unlock you can reproduce** on a device meeting the
   preconditions — start at [`docs/UNLOCK_RUNBOOK.ja.md`](docs/UNLOCK_RUNBOOK.ja.md)
   (Japanese; the step tables and commands are language-neutral).
2. **An experiment cycle for unlocked devices** — fastboot-window catching,
   flashing, and a one-photograph readout of kernel results through a screen
   probe.
3. **A guaranteed way back** — `firmware/kernel_stock.bin` restores Android
   from any experiment.

## Start here (by goal)

| Goal | Read |
|---|---|
| **Run the unlock** | [`docs/UNLOCK_RUNBOOK.ja.md`](docs/UNLOCK_RUNBOOK.ja.md) (full procedure, verification, failure playbook) |
| The unlock story and its record | [`docs/ANE_LX2J_BOOTLOADER_UNLOCK_20261002.ja.md`](docs/ANE_LX2J_BOOTLOADER_UNLOCK_20261002.ja.md) ([English](docs/ANE_LX2J_BOOTLOADER_UNLOCK_20261002.md)) |
| Flash an experiment kernel | [`docs/ANE_BOOT_CONTRACT.md`](docs/ANE_BOOT_CONTRACT.md) (boot contract) + the cycle section below |
| Port an alternative OS | [`docs/ANE_LX2J_PORT.ja.md`](docs/ANE_LX2J_PORT.ja.md) ([English](docs/ANE_LX2J_PORT.md)) — a worked application of the boot contract |
| Look up past experiments | [`docs/journal/INDEX.md`](docs/journal/INDEX.md) (index to the experiment ledger) |

## The unlock in one view

Five gates, in order. Full detail in the RUNBOOK:

1. **Downgrade** EMUI 9.1 → 8.0 (Windows + HiSuite; dload cannot cross the
   major-version boundary — measured). Installers are
   [mirrored on the Internet Archive](https://archive.org/details/p20lite-ane-lx2j-hisuite-tools).
2. **root** via CVE-2019-2215 (the SELinux bypass needs the constant
   difference `avc_cache - fair_sched_class = 0x134c838`; the proven build is
   bundled in `unlock/backup/`).
3. **Clear FBLOCK** (`hisi-nve w FBLOCK 0`; binary bundled in `unlock/tools/`).
4. **The OEM unlock toggle** (greyed out until the device has had internet
   for a while).
5. **Write USRKEY** (`hisi-nve w USRKEY` is a no-op on this device → edit the
   nvme image directly; `tools/unlock/write_usrkey_direct.sh`).
6. `fastboot oem unlock <16-char code>`

Every dependency is bundled in this repository: the exploit binary, the
hisi-nve binaries, the CVE source, and the nvme record images.

## Directory layout

```
docs/       contracts and procedures (UNLOCK_RUNBOOK.ja.md for the unlock,
            ANE_BOOT_CONTRACT.md for the boot contract)
  journal/      the experiment ledger (nightly records, time-series logs);
                INDEX.md is the index
tools/      scripts that drive and analyze the device (by role)
  flows/      cycles you run: ane_logloop.sh, ane_autopilot.sh,
              ane_window_flash.sh, V21_LOOP.sh, ane_catcher.sh ...
  probes/     screen-painting .S probes + assemblers (ane_log_probe is the
              current readout tool)
  builders/   boot-image construction: mkane_stock_embed.py, mkane_bootimg.py
  diag/       device-state readers (USB monitors, raw fastboot, oem log)
  analyze/    host-side analysis (DT, packages, dump decoding)
  unlock/     the unlock-era scripts, sorted by stage
  verify/     host verifiers + QEMU proofs (run before flashing)
  usbtool/    PCUI/AT USB probing (usbtool-*.py)
  apktool/    apktool.jar (local convenience copy)
  archive_experiments/   versioned experiment scripts, kept as record only
artifacts/  images ready to `fastboot flash kernel` (mostly local-only per
            .gitignore; the current screen reader is tracked)
firmware/   stock firmware and reference data
  kernel_stock.bin      25 MB extracted stock kernel (restores Android)
  ane_dtb/              the device's own DTB + flattened properties
  azrom/                stock firmware archives (13 GB, gitignored)
  ane_pstore_readback/  pstore readback records
logs/       automation logs and evidence
  usb_runs/     USB re-enumeration logs
  forensics/    snap_* device-state snapshots
  misc/         catch_lk / dumps / nightly logs
  night/        overnight loop ring logs
unlock/     the complete bootloader-unlock record (software-only):
  backup/         ANE-LX2J_20261002 snapshot: nvme before/after/installed,
                  frp_original, misc, oeminfo, the proven exploit binary,
                  MD5SUMS
  tools/          hisi-nve binaries (aarch64/armv7)
  cve-source/     CVE-2019-2215 source (constants already set to 0x134c838)
  working-notes/  the winning-configuration notes
  device-dumps/   nvme/USRKEY, oeminfo gamma, fastboot_LK.bin, dts_stock.bin
  lk/ lk_asm/     LK disassembly (lk_asm is local-only)
  pz_poc.c        the original PoC, kept for provenance
refs/       reference sources (hisifb display stack, HwProjectMenu.apk)
```

## Running an experiment cycle

1. Get a fastboot window: `adb reboot bootloader` from Android (no combo
   needed), or the ~2.5-7 minute window after a failed cold boot (the LK
   failure-streak behaviour is in `docs/ANE_BOOT_CONTRACT.md` §12).
2. Flash the experiment: `fastboot -s <serial> flash kernel artifacts/<img>`.
3. The kernel writes its step-mark record and parks (early-park vectors keep
   the device out of eRecovery).
4. In the next window, flash the **log probe**
   (`artifacts/fullerene-ane-log-probe-stock.img`) and reboot. It renders the
   mark record + the kernel log on screen, readable in one phone photograph.
5. Restore stock: `fastboot flash kernel firmware/kernel_stock.bin` — resets
   the failure counter and brings Android back.

`tools/flows/ane_logloop.sh` chains all of this automatically.

Note: most flows assume the device serial `SCV7N18927000473` pinned with
`-s`; substitute your own unit. Some scripts still `cd ~/dev/p20-root` —
that working tree remains the live home of the large binaries this repo's
.gitignore deliberately keeps out of git.

## The screen console (why a photograph works)

- The log probe renders 14 rows x 45 columns of 8x8 glyphs (3x scale): the
  last 540 chars of the kernel log plus the 90-char mark record.
- The kernel mirrors every UART byte into a RAM tee and flushes it into the
  ramoops pmsg zone after the MMU is up; the probe reads it from there.
- The visible budget is ~500 scanlines (12-14 rows) before the LK's unlock
  notice area.
- Font note: the bundled font (public-domain VGA 8x8) stores rows LSB-first;
  the renderer scans MSB-first, so the table must be bit-reversed at
  generation time or every glyph comes out mirrored (measured pitfall).

## Key findings (full record: docs/ANE_BOOT_CONTRACT.md)

- Boot progress is trackable through step marks. Mark `a` (MMU live + first
  console write) was cleared by making the MMIO attribute table
  per-platform.
- Reaching the MMU is **probabilistically flaky**: identical builds sometimes
  stop at mark 9, sometimes run to mark k. Re-run 2-3x before concluding.
- The LK keeps a failure-streak counter: the first cold failure opens a
  fastboot window, an immediate second one falls through to eRecovery. A
  successful stock boot resets the streak.
- `fastboot boot` stays refused after unlock (measured): every kernel test is
  flash → boot → (halt) → button recovery.
- The readout is one close-up phone photograph; no webcam setting resolves
  the glyph pitch (measured at multiple resolutions).

## Firmware (research reference)

`firmware/azrom/` holds the stock firmware of the ANE family
(Android 8.0 / EMUI 8.0: this unit's KDDI build, the C719 open-market
builds, ANE-TL00 CN). `firmware/kernel_stock.bin` is the extracted,
sha256-verified stock kernel.

These oversized binaries cannot live in a git remote, so they are preserved
on the **Internet Archive as the firmware corpus the study was verified
against**. The purpose is not warez distribution: it is to let anyone
independently verify the study's measurements against the same firmware
bytes, and to keep the work reproducible if the public mirrors disappear.

| Item | Contents |
|---|---|
| [p20lite-ane-lx2j-stock-firmware](https://archive.org/details/p20lite-ane-lx2j-stock-firmware) | the 5 unmodified stock packages used in the study (8.0.0.110 C635 / 8.0.0.127 C719 kddi + open-market / 8.0.0.202 C719 / 8.0.0.151 C01) + extracted `kernel_stock.bin` |

How the study used them:
- **8.0.0.127(C719)** — source of the recovered kernel symbol layout; the
  SELinux-bypass constant `avc_cache - fair_sched_class = 0x134c838` was
  derived from it.
- **8.0.0.110(C635)** — the in-major downgrade target (kernel 4.4.23), the
  build the published CVE-2019-2215 research applies to; the basis of
  RUNBOOK gates A/B.
- All packages — primary material for analyzing boot-image headers, recovery
  checks and the update-verification flow (`docs/ANE_BOOT_CONTRACT.md` §1-4).

No patched images, unlock codes, or paid-service tooling are included. The
unlock method itself relies on published research (CVE-2019-2215, Project
Zero); its reproduction procedure is documented in this repository.

Download everything:
```
ia download p20lite-ane-lx2j-stock-firmware
```
Per-file downloads are on the item page. (`ia` CLI: `pip install
internetarchive` or `uv tool install internetarchive`.)

## HiSuite (official installers used in the downgrade verification)

The RUNBOOK's gate A works only through the vendor's own PC tool HiSuite and
its version-switch feature (dload/SD cannot cross the major-version boundary
— verified across seven differently-constructed packages, see
`docs/ANE_BOOT_CONTRACT.md`). The official builds used in the verification
are preserved on the Internet Archive, because the vendor's download URLs
are not guaranteed to persist:

| Item | Contents |
|---|---|
| [p20lite-ane-lx2j-hisuite-tools](https://archive.org/details/p20lite-ane-lx2j-hisuite-tools) | the official HiSuite installers used (current W00018218 / 10.0.0.510 W00003542) + HiSuite Proxy V3.3.0 (third-party open-source helper, evaluated as a fallback) |

## Safety

- Flashing is limited to the `kernel` partition; the stock kernel is always
  available in `firmware/kernel_stock.bin` and restores the device.
- The tools never touch recovery partitions, configfs, or user data.
- Every nvme write in the unlock flow takes a backup first. That backup is
  the only way back — do not delete it.

## Verification expectations

Run the host-side checks before flashing anything new:

```
python3 tools/verify/verify_ane_early_vectors.py     # early-park vectors
python3 tools/verify/verify_base_loads.py            # base-load audit
bash    tools/flows/ane_logloop.sh --help 2>/dev/null || true
```

QEMU proofs for the probe assemblers live beside them
(`tools/probes/ane_log_probe.sh` refuses to package an image until its QEMU
render check passes).
