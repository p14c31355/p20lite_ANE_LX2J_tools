# ANE-LX2J (Huawei P20 Lite, JP variant) - bootloader unlock

Last measured 2026-10-01 (evening). Serial `SCV7N18927000473`.
Build **ANE-LX2J 9.1.0.132(C635E4R1P1)**, EMUI 9.1.0, Android 9 (SDK 28),
kernel **4.9.148** (built 2019-05-10), **security patch 2019-05-05**.

## THE BOTTOM LINE

Every free software-only route was measured and is closed on this build. The single missing
ingredient is the **16-char unlock code**, and nothing reachable without root or a VCOM
(`12d1:3609`) entry can produce it. Root via CVE-2019-2215 - the obvious choice for a May-2019
patch level - is **patched on this device** (see below).

## What is proven about the bootloader (fastboot)

`fastboot` works and `oem unlock` **exists**:

| command | result |
|---|---|
| `oem get-bootinfo` | `locked` |
| `oem lock-state info` | `FB LockState: LOCKED` / `USER LockState: LOCKED` |
| `oem get-product-model` | `ANE-LX2J` |
| `oem get-build-number` | `:ANE-LX2J 9.1.0.132(C635E4R1P1)` |
| `oem unlock`, `oem unlock-go`, `flashing unlock` | **`check password failed!`** (validates locally!) |
| `oem relock` | `stat not match` (so it is a real, recognised command) |
| `getvar max-download-size` | works (471859200) |
| **everything else** | `Command not allowed` |

Everything else was swept and answers the generic `Command not allowed`: `oem` device-info,
read_bsn, get_identifier_token, backdoor info, hwdog, get-hw-vendor, check-hw-security,
dump-chipid, enter-download, reboot-vcom, reboot-download, reboot-fastboot, readimei, read-sn,
get-sn, enable-adb, rma, get_config, sha1sum, dmesg, check-hw-security, enable-hw-factory,
continue-factory, factory-lock, and `getvar version/product/serialno/secure/unlocked/
battery-voltage/partition-*/all`. A nonsense command name gives the *same* generic error, so
that message cannot distinguish "unknown" from "known but refused"; the recognised commands
above are the ones that answer something else.

`fastboot flash` is **half-open**: the *download* half is accepted
(`Sending 'zzzNoSuchPart' OKAY`) but the **`Writing '...'` step is refused** with
`Command not allowed`. `erase`/`format` are refused outright. No write path exists.

`adb reboot download` does **not** enter a download/factory mode: the bootloader records
`ro.boot.bootreason=reboot,download` and then boots Android normally with `ro.boot.mode=normal`.

## What is proven about the Android side

- ADB works (`shell`, uid 2000, no root). `adb root` -> *adbd cannot run as root in production builds*.
- Block devices are enumerable (`/dev/block/bootdevice/by-name/`) but **reading them as shell is
  denied** (SELinux), so oeminfo/nvme cannot be dumped.
- After `settings put global oem_unlock_allowed 1`, `ro.oem_unlock_supported=1` and
  `sys.oem_unlock_allowed=1`. **This changes nothing in fastboot** - `flashing unlock` still answers
  `check password failed!`, i.e. Huawei diverts the AOSP path to its own code check.
- 203 binder services; none of them exposes oeminfo/nvme writes to shell.

## ProjectMenu / USB Port Settings - measured behaviour

Three choices: Google mode / **manufacture mode** / hisuite mode.

- **manufacture mode** sets `sys.usb.config=manufacture,adb` and exposes **5** interfaces on
  `12d1:107e`: two standard (ADB, HDB) plus three vendor ones (subclass 19, protocols 33/34/35).
  **Interface 1 (protocol 34) is the PCUI port**: it answers bare `AT` with `\r\nOK\r\n`, and
  every other command - `ATI`, `AT$QCDMG=115200`, `AT^GETPORTMODE`, `AT+CGSN`, `AT+CIMI`,
  `AT+PCUI*`, `AT$AUTH`, `AT$UNLOCK` - returns `\r\nno permission\r\n`. Interface 2 is silent,
  interface 0 times out on write.
- The gate is **not** host authorisation: it stays shut with USB debugging on *and* the host
  already authorised for ADB. `atcmdserver` (root, running, started from
  `/vendor/etc/init/init.manufacture.rc`), `diagserver` and `hdbd` are all running; no
  `/dev/ttyUSB*` is created, so the ports must be driven with libusb, not pyserial.
- **hisuite mode** sets `hisuite,mtp,mass_storage,adb`, exposes no AT channel at all, and makes the
  device re-enumerate every few seconds.
- **manufacture mode + reboot** also makes it re-enumerate every ~5 s (libusb then gets
  `Resource busy`). Revert to Google mode to get a stable device back.
- `sys.usb.config` / `persist.sys.usb.config` **cannot be set from shell** (SELinux), and
  `service call usb 1 s16 'manufacture,adb'` returns an error parcel and does not change it -
  only the ProjectMenu can, which is why the user has to touch the device.
- **ProjectMenu components are not startable from shell**: its manifest declares
  `android:sharedUserId="android.uid.system"` and every exported component carries
  `android:permission="android.security.SECURITY_ACTIVITY"`
  (`signatureOrSystem`). Receiver handles secret codes 2846579 and 34773.
  The APK itself is resource-only (`res/raw/speaker.mp3` + layouts); the code lives in the
  framework, which shell cannot read.
- `12d1:3609` (HUAWEI USB COM 1.0 / the VCOM download door) is **never presented** - not via the
  menu, not after a reboot, not via `adb reboot download`, not via any fastboot `oem` command.
- `/vendor/bin/se_recoverFactory` (world-executable, TEE-based: `TEEC_*`) is the *factory-reset /
  recovery-image* mechanism (`ro.image`, `recoveryimage`, `bootimage`), **not** a testpoint switch.

## Root: CVE-2019-2215 is PATCHED here

The build looks like the ideal target (patch level 2019-05-05, kernel 4.9.148, `CONFIG_DEBUG_LIST`
off, `CONFIG_ARM64_UAO` off, `CONFIG_SLAB_FREELIST_RANDOM` off, `CONFIG_PANIC_ON_OOPS` off, and
Huawei's own October-2019 advisory listing the P20 lite). **It is not.**

- Kernel config (readable as shell via `cat /proc/config.gz`): `CONFIG_DEBUG_SPINLOCK=y`,
  `CONFIG_DEBUG_LOCK_ALLOC` not set (so `spinlock_t` is 24 bytes and the waitqueue's `task_list`
  sits at wait+0x18, one iovec index further along than the Project-Zero PoC assumes),
  `CONFIG_ARM64_VA_BITS=39`, `CONFIG_RANDOMIZE_BASE=y`, `CONFIG_SECURITY_SELINUX_DEVELOP` not set,
  `CONFIG_KALLSYMS_ALL=y`, `CONFIG_DEBUG_INFO=y`.
- Source check (`turex/android_kernel_huawei_hi6250`, branch `android-9`,
  `drivers/android/binder.c`) shows the fix, and the git history pins its provenance:
  commit `e9134422f29927c813a46cf513b26e4138c85862` (Eric Biggers, 2021-12-10,
  backport of upstream `a880b28a71e39013e357fd3adccd1d8a31bc69a8`) only *replaced*
  `wake_up_poll(&thread->wait, POLLHUP | POLLFREE)` with `wake_up_pollfree()`.
  That commit carries `Fixes: f5cb779ba163 ("ANDROID: binder: remove waitqueue when
  thread exits.")` - and f5cb779ba163 *is* the original CVE-2019-2215 fix that AOSP put
  into the android-4.9 branch in Feb 2018. So the fix predates the 2021 backport and is
  present in this 2019-05 build.
- Runtime check 1: with `epoll_ctl(ADD)` -> `ioctl(BINDER_THREAD_EXIT)` -> `epoll_ctl(DEL)`
  all returning 0, the freed `binder_thread` reallocated with a controlled iovec array
  (`writev`, 25 x 16 B, `iovec[10]` overlaying the waitqueue) shows **no corruption** -
  `writev()` returns exactly 0x2000 and the leaked page is zeros. The polled waitqueue
  really is `&thread->wait` (confirmed in source), so the absence of corruption is the fix
  at work.
- Runtime check 2 (`~/dev/p20-root/probe_uaf.c`): ADD -> THREAD_EXIT -> DEL with **no**
  reallocation. Without the fix, DEL must `remove_wait_queue()` on the freed waitqueue and
  spin on its non-zero lock word; instead DEL returns 0 instantly, i.e. the wait entry was
  already removed at thread exit.
- Runtime check 3 (`~/dev/p20-root/probe_poll.c`) kills the only alternative explanation for
  check 2 (that `binder_poll()` never registered anything and DEL was trivially fast). A bare
  `poll()` on `/dev/binder` returns **POLLIN (revents=0x1), not POLLERR**, and the source shows
  `poll_wait(filp, &thread->wait, wait)` runs *before* the `binder_has_work()` check - so the
  waitqueue really is registered and the fix is the only remaining explanation.
- Provenance, from `git log -S POLLFREE -- drivers/android/binder.c`: the first commit to put
  POLLFREE handling into binder.c is `4b4bf0291e5` (2020-07-31, "hi6250: extract from
  Figo_PIE_EMUI9.1.0_opensource") - i.e. it came in with **Huawei's own published EMUI 9.1
  open-source kernel**, not as a later community patch. The hi6250 platform shares one kernel
  source across models, so stock ANE-LX2J EMUI 9.1 carries it too. (The 2021 commit
  `e9134422f29` only swapped `wake_up_poll(POLLFREE)` for `wake_up_pollfree()`.)

Harness left on the host: `~/dev/p20-root/` (`pz.c` = leak probe with runtime-tunable iovec
`shift` and `n_iov`; built with `~/Android/Sdk/ndk/28.2.13676358/.../aarch64-linux-android28-clang`,
`-O2`; pushed to `/data/local/tmp/pz`). `~/dev/temproot-huawei` (llccd, P20 Pro),
`~/dev/p20lite-cve` (willboka, P20 Lite 4.4.23; `STRUCT_CRED_OFFSET 0x618`,
`SECURITY_OFFSET_IN_CREDS 0x78` - both agree with the 4.9 layout analysis) are the reference ports.
The exploit needs **no kernel symbols**: `cred` is found by scanning the leaked task_struct page
and validated against `getuid()`, and the KASLR slide falls out of `cred->user_ns - &init_user_ns`.

## Routes left (all cost something)

### Huawei's kernel source IS obtainable, and it is a source-audit goldmine

`turex/android_kernel_huawei_hi6250`, branch `android-9`, root commit
`4b4bf0291e5` ("hi6250: extract from Figo_PIE_EMUI9.1.0_opensource", 2020-07-31) is
**Huawei's own published EMUI 9.1 kernel source** for the hi6250 platform, which the
ANE-LX2J shares. Get a file without a full clone:
`git clone --filter=blob:none --no-checkout --single-branch -b android-9 <url>` then
`git show <sha>:drivers/android/binder.c`.

**Inference rule that makes this usable**: the drop is a *later* 9.1.0.x than this
device's 9.1.0.132 (2019-05-10), so a fix that is **missing** from the drop is
**certainly** missing from the device. The converse does not hold - a fix present in
the drop may have arrived after 9.1.0.132. Use the branch **root commit** (Huawei's
content), not branch HEAD (which carries community backports).

Huawei's binder is an **older fork** than the AOSP android-4.9 tip. Fingerprint of the
root-commit binder.c: `tmp_ref` yes (Jan-2019 refactor), `user_buffer_offset` still
present (so `bde4a19fc04f` "use userspace pointer as base of buffer space" was NOT
taken), `binder_alloc_copy_to_buffer`/`from_buffer` absent, `secctx_sz` present.

Consequences, each checked against the source:

- **CVE-2019-2215**: patched. `wake_up_poll(&thread->wait, POLLHUP | POLLFREE)` is
  already there; stable 4.9.y has had it since `a494a71146a1` (2018-01-05).
- **CVE-2020-0041**: **not applicable.** The bug (`num_valid` computed with `*`
  instead of `/ sizeof(binder_size_t)`, fix `2ea90f03ca40` / upstream `16981742717b`,
  2019-12-13) was *introduced* by the Feb-2019 backport `bde4a19fc04f`, which Huawei
  never took. Huawei computes it correctly as a pointer difference:
  `binder_validate_ptr(t->buffer, fda->parent, off_start, offp - off_start)`.
- **Bug 133758011 / "binder: fix possible UAF when freeing buffer"** (fix
  `dc734d732df4`, 2019-06-10): **LIVE on this device.** Huawei still has the pre-fix
  `binder_free_transaction()` (`if (t->buffer) t->buffer->transaction = NULL; kfree(t);`)
  and `struct binder_proc.tmp_ref` is still `int` rather than `atomic_t`. Race between
  `binder_free_transaction()` and `binder_ioctl(BC_FREE_BUFFER)` -> use-after-free,
  reachable unprivileged through `/dev/binder`.

Next candidates to audit the same way (all post-date 2019-05, all need the fix's
prerequisite to be present in Huawei's fork): `a5b0e8dda9a2` (2020-10-09, "binder: fix
UAF when releasing todo list"), `1427acbb8b79` (2020-07-27, "Prevent context manager
from incrementing ref 0"), `699e4947e350` (2022-08-01, "fix UAF of ref->proc").
AOSP history source: `https://api.github.com/repos/aosp-mirror/kernel_common/commits
?path=drivers/android/binder.c&sha=deprecated%2Fandroid-4.9-q`.

Turning a race-window UAF into creds is still a full exploit-development effort; the
bug being live is necessary but not sufficient.

## binder security audit: what Huawei's fork actually missed

Method: take every `drivers/android/binder.c` fix on AOSP's android-4.9-q branch that
post-dates this build (2019-05-10), then test Huawei's **root-commit** source for the
fix. Commit list source:
`https://api.github.com/repos/aosp-mirror/kernel_common/commits?path=drivers/android/binder.c&sha=deprecated%2Fandroid-4.9-q&per_page=100`
(`python3` is the only sane way to read the JSON; use `write_file` + `bash` for the
script - long inline commands get blocked).

Result table (Huawei's state -> verdict):

| fix | date | bug | verdict on this device |
|---|---|---|---|
| `a494a71146a1` + `b6c6212514fe` | 2018-01/02 | **CVE-2019-2215** | **patched** (`wake_up_poll(POLLHUP|POLLFREE)` already present) |
| `d29b73e6f441` | 2018-11-06 | **CVE-2019-2025** (Bug 116855682) "malicious free of live buffer" | **patched** - Huawei's `BC_FREE_BUFFER` already uses `IS_ERR_OR_NULL`, `-EPERM` and the "unreturned or currently freeing buffer" message |
| `f65c15f74bbe` | 2019-04-24 | Bug 130571081 secctx `extra_buffers_size` integer overflow | **vulnerable** - Huawei line 3359 is a bare `extra_buffers_size += ALIGN(secctx_sz, sizeof(u64));` with no overflow guard. Reachability doubtful: `secctx_sz` comes from the policy, not the attacker |
| `dc734d732df4` | 2019-06-10 | **Bug 133758011** `binder_free_transaction` vs `BC_FREE_BUFFER` race | **vulnerable** - pre-fix body, `struct binder_proc.tmp_ref` still `int` |
| `76d4c949d9b0` | 2019-07-09 | Bug 136210786 SG buffer end | different SG code shape in Huawei; probably not applicable |
| `2ea90f03ca40` | 2019-12-13 | **CVE-2020-0041** `num_valid` computed with `*` | **not applicable** - needs `bde4a19fc04f`, which Huawei never took |
| `1427acbb8b79` | 2020-07-27 | context manager incrementing ref 0 -> self-transaction corruption | present, but needs `BINDER_SET_CONTEXT_MGR` (held by servicemanager) -> not reachable from shell |
| `a5b0e8dda9a2` | 2020-10-09 | **UAF when releasing todo list** | **vulnerable** - Huawei's `binder_release_work` still calls `binder_dequeue_work_head(proc, list)` with no inner lock |
| `699e4947e350` | 2022-08-01 | UAF of `ref->proc` race | needs newer code |

So the two live, unprivileged-reachable bugs are the **two teardown races** (Bug 133758011
and the todo-list UAF). Both yield a use-after-free with a NULL write (Bug 133758011 writes
`NULL` into the freed object at the `buffer`/`transaction` offset); both need race winning
plus heap grooming plus a primitive chain before they are worth anything. The clean
single-line bug (CVE-2020-0041) is exactly the one Huawei is immune to, because their fork
predates its introduction.

Non-binder leads also checked and closed: `/vendor/bin/se_recoverFactory` is world-executable
but SELinux refuses `execve` from the shell domain (`Permission denied`); `/system/bin/hwnff`
is only a client for `/dev/socket/hwnff` (markers `HWNFFDATASTART`/`HWNFFDATAEND`,
`hwnff.server.start`) and has nothing to do with NV or testpoint; `/system/bin/hw` is a
directory of HAL binaries.

### Exploitability of Bug 133758011: the trigger, and why it stalls

The race is between `binder_free_transaction(in_reply_to)` (called from
`binder_transaction()`'s reply path, Huawei line 3624, i.e. in the *replier's*
context) and the `BC_FREE_BUFFER` handler's
`buffer->transaction->buffer = NULL; buffer->transaction = NULL;`. Both touch the
same `binder_transaction`, and `in_reply_to->buffer` is a buffer of the
**transaction's target** - so **the racer must be the target of the transaction**,
not the sender. The fix wraps both sides in `binder_inner_proc_lock(target_proc)`.

Primitive: `NULL` (8 bytes) written at `freed_binder_transaction + offsetof(buffer)`.

Getting there means becoming a transaction target, which needs a binder node that
some other process will send to. Measured blockers:

- `BINDER_SET_CONTEXT_MGR` -> **EBUSY on both `/dev/binder` and `/dev/hwbinder`**
  (servicemanager / hwservicemanager hold them). `/dev/vndbinder` is not even
  openable by the shell domain (`Permission denied`). So the "be the context
  manager, handle 0 = my own node, self-transaction" shortcut is closed.
- `shell`'s SELinux policy (readable at `/system/etc/selinux/plat_sepolicy.cil`,
  `/vendor/etc/selinux/vendor_sepolicy.cil`) grants:
  `(allow shell servicemanager (service_manager (list)))` and
  `(allow shell base_typeattr_275 (service_manager (find)))` - **no `add`**.
  So we cannot publish our own node through `addService` either.
- Remaining possibility: get a handle to a shell-allowed service (`find` +
  `transfer`) and hand it our node as a callback argument, hoping it calls back -
  a narrowing search over services plus full Parcel marshalling by hand.

Steps still required even if the race is reached: win it, groom the freed
`binder_transaction` slot, convert a NULL write into a usable primitive, chain to
cred, then rewrite FBLOCK/USRKEY in the nvme partition, then `fastboot oem
unlock`. That is a research project, not a session.

## Can the paid tool be re-implemented? (measured answer: no, from outside)

The question that matters: DC-Phoenix's "enable software testpoint" works over plain
ADB with no root, so there must be an existing privileged path. Every candidate was
tested and is closed:

- **The AT channel rejects everything except a bare `AT`.** On the PCUI port
  (interface 1, protocol 34) with the device in manufacture mode, `AT` -> `OK`, but
  `ATI`, `AT+CGSN`, `AT^VERSION?`, `AT^GETPORTMODE`, `AT^HWVER`, `AT^NVRDEX?`,
  `AT^U2DIAG?`, `AT^CARDLOCK?`, `AT^SFM?`, `AT^SFM=0` and **`AT^SFM=1`** all reply
  `no permission`. `AT^SFM=1` (Huawei's "switch to factory mode" command, documented
  for their modems) was the best candidate for the software-testpoint trigger and it
  is refused too. So the gate is not a command allow-list gap - the channel itself is
  gated, and that gate is the paid tool's actual asset. `AT^NVWREX` (NV write, the
  "universal unlock") was deliberately NOT sent: a wrong index/value can damage NV.
- **`AT` needs a CR terminator.** Without the trailing `\r` the port answers
  `no permission` even for a bare `AT`; with it, `OK`. Cost me a bogus negative - a
  positive control on the same port caught it.
- **`12d1:3609` is never produced by the Android USB stack.** Every `idProduct` in
  every init file is 0x103A / 0x107e / 0x108a / 0x2d00-0x2d05 / 0x4ee9 / 1037, and
  `grep -rn 3609 /vendor/etc/init/ /system/etc/init/` is empty. Even the recovery
  init's `sys.usb.config=manufacture,adb` handler writes `idProduct 107e` with
  `functions hw_acm,mass_storage,adb,hdb` and `port_mode 14`. So 3609 comes from the
  boot ROM, i.e. it needs a persistent flag that only the boot chain reads.
- **Nothing shell can reach writes such a flag**: `/dev/socket/oeminfo_nvm`
  `connect()` -> Permission denied (and `/vendor/bin/oeminfo_nvm_server` is
  unreadable); block devices denied; `/vendor/bin/se_recoverFactory` -> execve denied;
  `/sys/devices/virtual/android_usb/android0/port_mode` -> Permission denied;
  `hisi_usb_class` and `hisi-mailbox` are read-only symlink trees (only `uevent`,
  which is denied); SELinux gives shell `service_manager { list find }` but no `add`;
  `BINDER_SET_CONTEXT_MGR` is EBUSY on /dev/binder and /dev/hwbinder and /dev/vndbinder
  is not openable at all. `/dev/socket/property_service` and `/dev/socket/logd` are
  connectable but no init action turns a property into a partition write
  (`grep -rn 'write /dev/block' /vendor/etc/init/ /system/etc/init/` is empty).

Conclusions: the tool's mechanism is either a vendor secret (the manufacture-mode
authentication) or a bundled exploit. Neither is observable from the host side, so a
clean-room re-implementation is not available with what we can measure.

## Paid route: cost and payment (measured 2026-10-01)

Corrected estimate. The "500-800 JPY" figure was wrong.

- **Android 8+ services are HCU Client only and require a TIME LICENSE**
  (stated verbatim on dc-unlocker.com/buy). This device is Android 9, so it falls
  under this rule - the cheap per-credit "read bootloader code" (4 credits, 1 credit
  = 1 EUR) does NOT apply.
- HCU + DC-Phoenix timed license: **3 days 19 EUR**, 30 days 39 EUR, 1 year 79 EUR,
  2 years 99 EUR. At 1 EUR = 178.4 JPY (2026-10-01) that is ~3,400 / ~7,000 / ~14,100
  / ~17,700 JPY. The cheapest viable purchase is the 3-day tier at ~3,400 JPY.
- Payment methods (user agreement, verbatim): "Hipay, PayU, Bank transfer, Webmoney,
  SMS payments and Bitcoin". PayPal is additionally accepted but **only from VERIFIED
  accounts** - an unverified payment is received and then refunded
  (/payment-refunded). For Japan, verified PayPal or a card via Hipay/PayU are the
  practical choices; Bitcoin works but is explicitly non-refundable.
- Practical blockers to plan for: **HCU and DC-Phoenix are Windows software** (Wine or
  a Windows VM with USB passthrough); the **timed license is locked to the first PC
  used** (auto-relocks to a new PC after 48 h), so start it on the machine that will
  do the work; the phone must start in ADB mode with USB debugging - exactly the state
  this device is already in.

## What the paid service ACTUALLY does (settled 2026-10-01)

This corrects the earlier testpoint/VCOM hypothesis for the ADB path. Per the XDA
guide for this device generation (Mate SE, same EMUI family) the whole flow is:

1. dialer `##2846579##` -> Background settings -> USB ports settings ->
   **Manufacture mode** (the state we already reach ourselves), then
2. HCU Client **logs into the vendor account**, the server verifies the account's
   credits / timed license, and
3. the server returns the bootloader code (Read Bootloader code).

The old DC-Unlocker flow is identical in shape: click "Server", authenticate with
the purchased username/password, then "Unlocking -> Read Bootloading code".

Implications:
- The capability lives **server-side**, gated on a paid account. The client is only a
  front end. A pirated/cracked client therefore does not carry the entitlement - it
  cannot get a code from the server. (And cracked unlock tooling is a known malware
  vector pointed straight at the phone's bootloader and the host PC.)
- Testpoint / VCOM 3609 is NOT what the ADB-mode service uses, so our earlier hunt for
  a way to produce 3609 was aimed at the wrong door. Nothing to re-implement locally.
- Practical bottom line: ~19 EUR buys server-side authorization, and this device is
  already in the prerequisite state. Cost/benefit vs. the closed exploit route is
  decisive.

## Two dead ends, measured (2026-10-01)

### "Make the Android kernel fault" does not open the UAF entry

The blocker for Bug 133758011 is AUTHORITY (SELinux policy), not information, so a
fault cannot help - LSM hooks are policy decisions, unchanged by a fault. And
diagnostically there is nothing to gain either, all measured on the device:

- `# CONFIG_VT is not set` -> no virtual terminal, hence **no framebuffer console**:
  a kernel oops prints nowhere the user could photograph.
- `CONFIG_PANIC_ON_OOPS_VALUE=0` (`# CONFIG_PANIC_ON_OOPS is not set`) -> an oops does
  NOT reboot the device.
- `adb shell dmesg` -> `klogctl: Operation not permitted`. `/proc/kmsg` -> Permission
  denied. `logcat -g` lists only main/system/crash - **logd exposes no kernel buffer**,
  so `logcat -b kernel` is empty by construction.
- `/sys/fs/pstore` is `drwxr-x--- root root` -> pstore (CONFIG_PSTORE_CONSOLE/PMSG/RAM
  are all =y) is the ONLY sink and it is root-only.
- `/proc/sysrq-trigger` and `/proc/sys/kernel/sysrq` -> Permission denied
  (CONFIG_MAGIC_SYSRQ=y, DEFAULT_ENABLE=0x1).

So a fault yields neither a KASLR leak nor a mode change - and a leak would not open
the gate anyway, because the gate is authority, not knowledge.

### Bellows as XBL requires the unlock it is meant to replace

fullerene's own UEFI bootloader is `bellows` (workspace member, `x86_64-unknown-uefi`,
plus an ESP32/xtensa entry). Installing it in place of the Pixel's XBL is circular:

- Primary source, Qualcomm Boot Guide: "The **PBL loads and authenticates the XBL**
  from the boot device." Authentication is against the OEM key fused in the SoC; a
  retail Pixel has secure boot on and the key programmed.
- Linaro: the open signing path (`qtestsign`/`patchxbl`) covers development boards only
  (rb3, rb5, db410c, db820c) - retail devices need Qualcomm's own sectools.
- Shape note: Bellows is a UEFI application, and on Qualcomm the UEFI stage lives
  *inside* XBL while fastboot lives in ABL. So the realistic installation is
  chainloading from ABL the way U-Boot does - which needs the device unlocked first.

### The three doors, all closed

For a locked retail Kirin/Snapdragon device the only entries are (1) the OEM's unlock
authorization (the paid path), (2) a signed-programmer EDL/9008 path (needs the
vendor's programmer, normally test points - forbidden here), (3) a userspace/kernel
exploit chain (blocked at the entry by SELinux). Nothing else exists.

## THE VIABLE FREE ROUTE: downgrade to Android 8.0.0, then CVE-2019-2215 (2026-10-01)

This supersedes the "nothing left" conclusion. The insight is a **kernel generation
change**, not a version wobble.

- Our device runs Android 9 / **kernel 4.9.148**, in which CVE-2019-2215 is fixed
  (measured three ways).
- `willboka/CVE-2019-2215-HuaweiP20Lite` (cloned at ~/dev/p20lite-cve) states verbatim:
  "an exploit for CVE-2019-2215 on Huawei P20lite in version **Android 8.0.0**. Kernel is
  in version **4.4.23**" - and it is tested on a physical phone (demo.mp4). 4.4.23 is
  from June 2016, a year and a half before the January 2018 fix.
- So a downgrade to Android 8.0.0 buys a **vulnerable kernel generation**, not just an
  older build.

### Why the downgrade is reachable without an unlock

- `fastboot flash` and `fastboot boot` are both refused by the locked bootloader
  (measured: Sending always OKAY, then `Writing`/`Booting` -> "Command not allowed";
  the payload is irrelevant, the verb is not on the allow-list).
- **`dload` (SD-card UPDATE.APP / update_sd tree, Vol Up + Vol Down + Power) flashes
  OFFICIAL signed firmware with the bootloader locked** - it is the normal update path,
  so it is not circular. Reported working on a locked ANE-LX3 from EMUI 8.1 to 9.1.
- XDA records the exact same plan succeeding for a P20 Lite: "downgrade my P20 lite to a
  lower firmware because **dc-unlocker is not working with the last one** and I need to
  unlock my bootloader" -> "**It worked! I was able to obtain the code!!!**". Note this
  means the downgrade is a prerequisite even for the PAID tool.

### Firmware to look for (our CUST matters)

- ANE-LX2J **C635** (the Japan open-market cust, our device - NOT Rakuten): `8.0.0.110(C635)`,
  `8.0.0.151(C635)` (needrom lists 151 as OFFICIAL), `8.0.0.202(C719)`.
- Failures reported by others are cust/version mismatches: "Software install failed" or
  "the software package is not compatible with the current version". Some report the
  downgrade must be stepwise (9.1 -> 9.0 -> 8.0); others installed 8.0.0 directly.

### dload layout (the usual failure point)

Not `dload/UPDATE.APP` - the successful report used the extracted package tree:
`dload/update_sd.zip`, `dload/ANE-L01_hw_eu/update_sd_ANE-L01_hw_eu.zip`, etc.
Data is wiped. Charge above 30%.

### What still needs verifying

- The **kernel version of ANE-LX2J 8.0.0.x** must be confirmed: willboka's offsets are
  fixed for **4.4.23** (his device was an ANE-LX1). A different 4.4.x needs offset work,
  though the technique carries over.
- Anti-rollback risk is reported small ("it will come up with an error when something is
  wrong") but is not zero.

### Then

Build ~/dev/p20lite-cve, push to /data/local/tmp, run it as shell -> SELinux permissive
and root/cred escalation -> write the oeminfo boot flag ourselves -> `fastboot oem unlock`
works. No paid license needed.

### Firmware acquisition: what was tried (2026-10-01)

The exact package is `ANE-LX2J Anne-L22J 8.0.0.110(C635) - 05015ARD` (~2.4GB), and it is
scarce. Results of chasing it:

- **droidfilehost.com** (reached via getdroidtips) is an **ad-redirect farm**, not a file
  host - it bounced to a Steam store page. Dead end.
- **HalabTech** (`support.halabtech.com`, file id 172340) is titled `ANE-LX2J 8.0.0.110(C635)
  ROOT.HT8` but is only **8 MB** - it is a root file for their paid tool, not firmware. Their
  ANE-LX2J folder holds root files only (8.0.0.110/C635, 8.0.0.164/C636, 8.0.0.111/C719,
  8.0.0.127/C719, 8.0.0.202/C719, 9.1.0.150/C719), all login-walled.
- **azrom.net** (`/product/ane-lx2j-anne-l22j-8-0-0-110-c635-firmware/`) is real but **paid**
  (10,000 VND ~ 70 JPY); PayPal only appears for orders >= 5 USD, so it needs a wallet top-up.
- **needrom** lists `ANE-LX2J 8.0.0.151(C635)` as OFFICIAL - Android 8.0.0 plus our cust, i.e. the
  right target. Downloads need an account ("You must be logged for ROM download").
  **Its search cannot be driven by URL**: `?s=ANE-LX2J` -> "Nothing found", `?search=ANE-LX2J` ->
  bare homepage, and submitting the real form (`input[name=search]`, action `/`) yields a blank page
  under automation - results are JS-loaded. Browse the **Huawei -> "- Other Sub"** listings instead,
  or search the open web for `site:needrom.com ANE-LX2J`, which surfaces the entry title and page.
  That entry showed only ~9 downloads, so it may be partial - verify size and structure after
  downloading.
  **Trap**: needrom's Huawei packages are often **IDT/XML tool packages**, not `dload` - their own
  install text tells you to load an XML into Huawei's Windows tool. Insist on a tree containing
  `UPDATE.APP`; `.xml` + `.img` only means it is the wrong form for the SD-card route.
- **curl is blocked by the WAF** on these sites (TLS handshake reset / HTTP2 stream error,
  and the cert chain fails locally). A real browser gets through.
- Exact-phrase web searches for the archive name return little; the mirrors are walled.

**The downgrade is needed for the PAID route too** - the XDA report was "dc-unlocker is not
working with the last one", so Android 8.0.0 is a prerequisite either way. Getting the package
is therefore worth the effort under both plans.

### Browser tooling note (so this is not rediscovered)

Hermes' `browser_exec` needs a Chromium-family browser **with a DevTools port exposed**, and it
looks for `DevToolsActivePort` in the standard profile dirs (`~/.config/google-chrome`,
`~/.config/chromium`, ...). A normally-launched Chrome does not expose one. Working recipe:

    /usr/bin/google-chrome --user-data-dir=/home/placeless/.config/chromium \
        --remote-debugging-port=9222 --no-first-run --no-default-browser-check about:blank

(separate profile, so the user's real Chrome is untouched), then, if the harness still cannot
find it, write the port file the way Chrome would:

    printf '9222\n/devtools/browser/<uuid>\n' > ~/.config/chromium/DevToolsActivePort

with `<uuid>` taken from `curl -s http://127.0.0.1:9222/json/version`. Also set
`browser.use_real_profile false` via `hermes config set` - with it true the harness tries to
snapshot the user's **brave** profile at `~/.config/BraveSoftware/Brave-.../Default`, which does
not exist (brave here is a snap, so its real profile lives under `~/snap/brave/...`).

## CONFIRMED: the Android 8 kernel is 4.4.23 and CVE-2019-2215 is UNPATCHED

Primary source, no firmware download needed:

    https://github.com/HwFans/ANE_AL00_TL00_LX1_LX2_LX3_LX2J_HWV32_OR_EMUI8.0.0.151_opensource
    branch main, kernel source under kernel/  (455 MB repo)

Its `README_Version.txt` says the package is "released for the phone software version
Anne-AL00/TL00/LX1/LX2/LX3/LX2J/HWV32-8.0.0.151-C00", and `kernel/Makefile` reads:

    VERSION = 4   PATCHLEVEL = 4   SUBLEVEL = 23

**4.4.23 - exactly the kernel willboka's P20-Lite exploit targets.** And the fix markers in
`kernel/drivers/android/binder.c` settle the exploitability question:

| marker | 4.4.23 (Android 8) | 4.9.148 (our device) |
|---|---|---|
| `POLLFREE` | 0 | 0 |
| `wake_up_pollfree` | 0 | 2 |
| `ep_remove_wait_queue` | 0 | 1 |

The wakeup sites are the vulnerable shape - plain
`wake_up_interruptible_sync(&thread->wait)` / `wake_up_interruptible(&thread->wait)` in
`binder_wakeup_thread_ilocked` / `binder_wakeup_poll_threads_ilocked`, with no POLLFREE
wakeup anywhere. So the Android 8 build has no CVE-2019-2215 fix at all.

Consequences that de-risk the plan:
- The exploit's fixed offsets (derived on an ANE-LX1 4.4.23) should apply to an ANE-LX2J on
the same version - **and we now hold the matching kernel source, so offsets can be verified
or recomputed** instead of guessed.
- The exploit runs from unprivileged shell, so no unlock is needed to get root.
- `README_Version.txt` also warns "if your phone already enable secboot feature, please
decrypt or unlock the secboot feature first" - that applies to *flashing* a self-built
zImage, not to our path (official `dload` + a userspace exploit).

So the one remaining requirement is the **Android 8.0.0 (C635) image**, and now there is a
source-grounded reason for needing it rather than an inference.

### Mirror inventory for the firmware (found by search, all login/pay-walled)

- `vngsmservices.com` - ANE-LX2J "Anne-L22J 8.0.0.202(C719)" (C719, not our cust)
- `romdevelopers.com` - ANE-LX2J 8.0.0.202(C719)
- `halabtech` - ANE-LX2J 8.0.0.127(C719), 8.0.0.111(C719), 8.0.0.110(C635) ROOT.HT8 (8 MB, not firmware)
- `forum.imeisource.com` - ANE-LX2J 8.0.0.100a (C719)
- Note how many are C719: the Japanese ANE-LX2J family mostly circulates as **C719**, while our
  our unit is **C635** (Japan open market, not Rakuten) - only a handful of C635 packages exist, which is why this
  one is hard to source.
- needrom's own search box takes a `search` GET parameter but the results are AJAX-loaded, so
  a URL query returns an empty page; the entry appears in search-engine indexes as
  `ANE-LX2J (P20 lite ...) - 8.0.0.151(C635) - OFFICIAL` on the Huawei/Other Sub category, but
  the live listing no longer shows it. needrom blocks unknown URL params with "Security Filter
  Triggered".

### Cust, and a correction worth keeping straight

**The P20 Lite is NOT a Rakuten device.** The Rakuten unit is the **OPPO A5 2020** (see the
oppo-qualcomm-device-unlock skill); the two were conflated once and it caused loose reasoning
about cust. What actually drives firmware selection is the **cust code read from the device
itself**:

    ro.build.display.id = 9.1.0.132(C635E4R1P1)   -> cust = C635

The ANE-LX2J was sold in Japan SIM-free / through channels such as **mineo** (mineo's support
site carries P20 Lite software-update notices); **C635 is the Japanese open-market cust**. So
the required image is `ANE-LX2J 8.0.0.110(C635)` / `hw jp` regardless of which shop sold the
phone - the check is model + cust, not carrier.

Corollary for sourcing: the Japanese ANE-LX2J family mostly circulates as **C719** (KDDI and
similar), so C635 packages are rare - that is the whole reason this file is hard to find.

### GOT the firmware: verified contents (2026-10-01)

Source: a Google Drive share of
`ANE-LX2J_Anne-L22J_8.0.0.110(C635)_hw_jp_Firmware_Android_8.0.0_EMUI8.0.0_05015ARD.rar`
(id `1vtvv08sKc_KuSxwZ9VnwPTfpwBsFStJL`), 2,553,442,642 bytes = 2.55 GB.

Drive note: `uc?export=download&id=...` returns an HTML "virus scan warning" page for large
files. Parse the form from that page and use its fields - the working URL shape is
`https://drive.usercontent.google.com/download?id=<ID>&export=download&confirm=t&uuid=<UUID>`,
where UUID comes from the warning page. Range requests work (206), so `curl -C -` resumes.

Archive verified with `Everything is Ok`, 19 files / 6 folders, non-solid RAR5, Method
`m3:25`, uploaded by azROM.net. **Layout matches the XDA success report exactly:**

    Software/dload/update_sd.zip                              (2,064,931,292 bytes)
    Software/dload/ANE-L22J_hw_jp/update_sd_ANE-L22J_hw_jp.zip   (503,201,396 bytes)
    ReleaseDoc/... (Huawei release notes, checklists, Virus Scan Report.doc)

So the SD card must carry `dload/update_sd.zip` plus `dload/ANE-L22J_hw_jp/update_sd_ANE-L22J_hw_jp.zip`
- NOT `dload/UPDATE.APP` (that is the older generation's layout). No executables anywhere in
the archive. Timestamps are 2018-05-09, i.e. the original release.

### PITFALL: Linux p7zip cannot extract RAR data blocks

`7z l` on this file **works** (headers parse, names and sizes list fine) but `7z x` fails with
`ERROR: Unsupported Method` on every entry and produces 0-byte files. The distribution's p7zip
ships without the RAR codec, so the listing success makes it look like the download is corrupt
when the archive is perfect. Fix without root: fetch the official Linux build

    curl -sL -o /tmp/7zz.tar.xz https://www.7-zip.org/a/7z2301-linux-x64.tar.xz
    mkdir -p ~/opt/7zz && tar -xJf /tmp/7zz.tar.xz -C ~/opt/7zz
    ~/opt/7zz/7zz t <archive>      # -> Everything is Ok

(`7zz` from 7-zip.org has full RAR5 support; the `p7zip`/`7z` package does not.)

### SD card staged and ready (2026-10-01)

The 64 GB microSDXC was formatted **FAT32** (`mkfs.vfat -F 32 -n DLOAD /dev/sdb1` - exFAT will
not be read by the updater, and note Windows cannot make a >32 GB FAT32 volume, so this needs
Linux). Then the payload was placed as:

    /dload/update_sd.zip                         (2,064,931,292 bytes)
    /dload/ANE-L22J_hw_jp/update_sd_ANE-L22J_hw_jp.zip  (503,201,396 bytes)

Verified bit-exact by md5 against the extracted source:
`748724ab4f63af7e110de060b9032cb0` and `ef037f7a2d5aeee4e6133515cb3941fc`.

Note the payload is two `.zip` files, not a bare `UPDATE.APP`: the 4.34 GB `UPDATE.APP` lives
**inside** `update_sd.zip`, which is exactly how it fits on a FAT32 card (4 GB file limit).
`update_sd.zip` is signed by SignApk (`META-INF/CERT.RSA`, `otacert`) and its updater-script is
just `assert(compress_sd_update_from_zip("UPDATE.APP"))`.

`UPDATE.APP` internals worth remembering: partition entries `EFI PART / XLOADER / fastboot /
boot / xloader / kernel / vbmeta / bootfail_info / system`, header tag `HW7x27`, build stamp
`2018.04.19`, `SHA256RSA` + `CRC` metadata. **The kernel version is NOT greppable from
`UPDATE.APP`** - the kernel image is compressed, so there is no plain `Linux version` string -
and `SOFTWARE_VER_LIST.mbn` only holds `ANNEC00B000 / ANE-BD 1.0.0.1 / ANE-BD 1.0.0.999`. The
Kernel version is therefore confirmed *after* the flash with `cat /proc/version` (which must be
done before running the exploit anyway).

Baseline captured before flashing (for the after-comparison): `ANE-LX2J 9.1.0.132(C635E4R1P1)`,
Android 9 / SDK 28, patch 2019-05-05, `Linux version 4.9.148 ... #1 SMP PREEMPT Fri May 10
17:14:15 CST 2019`, battery 100%, /data 16 GB free.

### Building willboka's exploit with NDK 28 (recipe, three fixes needed)

Repo `~/dev/p20lite-cve`. The stock build instructions fail on a modern NDK; three fixes:

1. **`libsepol.a` is a prerequisite** and setools-android's *tool* modules break the build.
   `ndk-build` at the setools-android root also builds `seinfo`/`sesearch`/`sepolicy-inject`,
   which pull in `libapol` and die on `error: redefinition of 'swab'` (old code vs modern
   Bionic). We only need the library. `jni/libsepol/` has its **own** Android.mk, and
   `NDK_PROJECT_PATH` must point at a root containing `jni/`, so copy its *contents* into a
   throwaway project:

       rm -rf /tmp/sepol-build && mkdir -p /tmp/sepol-build/jni
       cp -r setools-android/jni/libsepol/. /tmp/sepol-build/jni/
       printf 'APP_ABI := arm64-v8a\nAPP_PLATFORM := android-21\n' > /tmp/sepol-build/jni/Application.mk
       NDK_PROJECT_PATH=/tmp/sepol-build $NDK/ndk-build
       cp /tmp/sepol-build/obj/local/arm64-v8a/libsepol.a ~/dev/p20lite-cve/

   (Copying the tree directly under `jni/` matters: the Android.mk lists sources as `src/...`
   relative to `$(LOCAL_PATH)`. Pointing `NDK_PROJECT_PATH` at `jni/libsepol` looks for
   `jni/libsepol/jni/Android.mk` and fails; copying only Android.mk up a level looks for
   `jni/src/...` and fails.)
2. **`APP_PLATFORM := android-16` in Application.mk is gone from NDK 28** (dropped after r23).
   Override on the command line: `APP_PLATFORM=android-21`.
3. **`PAGE_SIZE` is no longer exposed by modern Bionic** -> 19 errors in `cve_2019_2215.c`
   (`use of undeclared identifier 'PAGE_SIZE'`, and cascade errors like `invalid application of
   'sizeof' to an incomplete type 'unsigned long[]'`). Add to the cve-2019-2215 module in
   Android.mk:

       LOCAL_CFLAGS := -DPAGE_SIZE=4096

   Value is correct for this target: the device's own config gave `VA_BITS=39` with 3 levels
   (4 KB pages), and `THREAD_SIZE = PAGE_SIZE << 2` = 16 KB, the arm64 kernel stack.

Result: `[arm64-v8a] Executable : cve-2019-2215`, `libs/arm64-v8a/cve-2019-2215`, 96,648 bytes,
`ELF 64-bit LSB pie executable, ARM aarch64`, interpreter `/system/bin/linker64`, needing only
libc/libm/libdl. `Makefile` has `push:` (adb push to /data/local/tmp + chmod).

**Do not run it before the downgrade** - it is written for 4.4.23 and the device is on 4.9.148
until the dload completes.

### FIRST dload ATTEMPT FAILED: "Incompatibility with current version"

The staged `8.0.0.110(C635)` package was refused by the updater with:

    Software install failed!
    Incompatibility with current version
    Please download the correct update package

Diagnosis: the package carries a **compatibility list** and it does not include our current
state. `SOFTWARE_VER_LIST.mbn` inside `update_sd.zip` contains exactly:

    ANNEC00B000
    ANE-BD 1.0.0.1
    ANE-BD 1.0.0.999

Our unit is `ANE-LX2J 9.1.0.132(C635E4R1P1)`, i.e. cust C635 - absent from that list. (The
updater compares against **oeminfo**, not the build string, so a rebranded second-hand unit can
mismatch what `ro.build.display.id` claims.)

Discounted theory: the widely repeated "downgrade one by one, EMUI 9.1 -> 9.0 -> 8.0" advice is
**unverified** - the Stack Exchange answer that states it gives no source and was challenged for
one, and for the P20 Lite the EMUI 9 line is **9.1 only** (listings read `9.0.0 / 9.1.0` meaning
Android 9.0 with EMUI 9.1), so there is no intermediate 9.0 release to step through.

Community-reported working routes, in order of practicality:
1. **HiSuite downgrade** (Huawei's own PC tool, free, Windows) - "downgrade to EMUI 8 via
   HiSuite" is the first suggestion from the XDA regulars. Caveat: it needs Huawei's update
   servers and this is a 2018 device, so availability is unproven.
2. **A real service ROM via dload** - note the XDA claim that "the dload method requires a
   service ROM, the firmware downloaded from FirmFinder is not suitable". Ours *is* service-format
   (ReleaseDoc with verify tables and release notes) yet was still refused, which points at the
   compatibility list rather than the package type.
3. **A rollback/debrand package** - the classic Huawei flow sets the device to a neutral key
   (`C900B300` for old devices) whose compatibility list accepts the target version. azrom lists a
   related artefact for the P20 Lite family: `ANE-L12J-Rebrand-OEM-FILE-CONVERT-TO-GLOBAL-FIX-OEM-MISSING.rar`
   (200 KB), so such files exist for ANE - just not (yet) for LX2J/C635.
4. Also worth noting: "Don't try to install dload FW for EMUI 8 if you are running EMUI 9"
   (XDA, -Alf-).

Next diagnostic: read the device's **oeminfo** rather than its build string -
`fastboot oem oeminforead-CUSTOM_VERSION`, `fastboot oem oeminforead-SYSTEM_VERSION`,
`fastboot oem get-build-number`, `fastboot getvar vendorcountry`. The fastboot allow-list on this
unit was restrictive (only `oem get-bootinfo` / `lock-state info` / `get-product-model` /
`get-build-number` / `getvar max-download-size` answered), so whether the `oeminforead-*` verbs
are permitted is itself an open measurement.

### VERDICT: the free route is blocked at the downgrade step (measured exhaustively)

The kernel analysis was correct - Android 8 on this model is 4.4.23 with CVE-2019-2215
unpatched, verified in Huawei's own OSS kernel source, and the public P20-Lite exploit is built
for exactly that version. What blocks the free route is that **the 4.4.23 image cannot be put on
the device**. Every entry was measured:

| route | result |
|---|---|
| `dload` of an EMUI 8 package from EMUI 9 | **refused**: "Incompatibility with current version" (our run), and first-hand XDA: "this DOES NOT WORK when you're on EMUI 9 ... every time" |
| forced dload | "a complete bust for me, 24 hours wasted" |
| HiSuite rollback | server-dependent. "I was finally able to rollback from HiSuite 11" (9.1.0.200 -> 8.0.0.163) but "I have not received the option to rollback after I re-upgraded to 9 since" - i.e. gone |
| edit oeminfo to satisfy the check | **writes blocked**: `oem oeminfowrite-*` -> `Command not allowed` (measured; reads of `oeminforead-SYSTEM_VERSION` / `-CUSTOM_VERSION` ARE allowed) |
| `fastboot flash` / `fastboot boot` | `Command not allowed` at the Writing/Booting stage (measured) |
| rollback / debrand package | none found for ANE-LX2J C635 |
| DC-Unlocker | **also needs the rollback**: "only if you can rollback to 8.0.0.146 or lower" |

Fastboot facts worth keeping (all measured this round):
- `oem get-product-model` -> `ANE-LX2J`; `oem get-build-number` -> `ANE-LX2J 9.1.0.132(C635E4R1P1)`
- `getvar vendorcountry` -> `hw/jp`
- `oem oeminforead-CUSTOM_VERSION` -> `ANE-LX2J-CUST 9.1.0.4(C635)`
- `oem oeminforead-SYSTEM_VERSION` -> `ANE-LX2J 9.1.0.132(C635E4R1P1)`
- **The unit is NOT rebranded** - oeminfo cust is C635, matching the package. Correct names that
  fail with `oem_nv_item error` are merely wrong item names; `Command not allowed` is a blocked
  verb. Use a bogus item name to test a verb's availability without touching real data.
- Unlike the XDA example (where SYSTEM_VERSION still held an EMUI 8 value on a 9.1 device), ours
  was updated to 9.1, so the compatibility check sees EMUI 9.

### What is left: HCU Client, which does NOT need the downgrade

The same XDA post separates the two paid tools: **DC-Unlocker needs the rollback** ("only if you
can rollback to 8.0.0.146 or lower"), but **HCU Client does not** - it works from **manufacture
mode + server authorization**, and we already know how to reach manufacture mode on this unit.
That is the one remaining route, at ~19 EUR / ~3,400 JPY for the 3-day license, plus Windows.

### The ReleaseDoc inside the package explains the refusal (and reveals a second path)

Our `8.0.0.110(C635)` package ships `ReleaseDoc/05015ARD+++_ReleaseDoc/`. Two documents matter.

**1. `Software Upgrade Guideline.docx` - the upgrade table lists only itself:**

> Historical Version Information Table - "The version listed in the following table can be
> upgraded to the target version."  | ANE-LX2J 8.0.0.110(C635) | 2018-04-16 |

So the package accepts *only* a device already on `8.0.0.110` - the same statement as the
`ANNEC00B000` / `ANE-BD 1.0.0.x` compatibility list. **This is a factory/repair package, not a
downgrade path.** Confirmed by the release notes:

    内部版本号：ANE-L22J 8.0.0.110(C635)
    外部版本号：ANE-LX2J 8.0.0.110(C635)
    版本用途：TA版本          <- TA (technical acceptance) = factory/test build
    是否建议服务放到device官网：否   <- "not recommended for the official site"

**2. The guideline defines TWO upgrade modes, and they are different code paths:**

| mode | how it is entered |
|---|---|
| **Normal upgrade** | dialer `*#*#2846579#*#*` -> ProjectMenu -> **Software Upgrade > SDCard Upgrade** -> OK |
| Forcible upgrade | power off, hold volume-up + volume-down + power (3 buttons) |

We used the **forcible** path (3 buttons), which is the one that ran the compatibility check and
failed. The **normal** path - ProjectMenu's own `Software Upgrade > SDCard Upgrade` - is the
procedure Huawei documents *for this very package* and is a separate entry point. Worth trying
before concluding anything.

Also from the guideline:
- Package layout (section 3.2): `dload/update_sd.zip` (main) +
  `dload/ANE-L22J_hw_jp/update_sd_ANE-L22J_hw_jp.zip` (customized data), and optionally a separate
  `Vendor/hw_jp_ANE-L22J/update_sd.zip` (carrier/country package). Our archive has the first two;
  the vendor package is absent, and `getvar vendorcountry` already reads `hw/jp` (matching), so it
  should not be needed.
- Section 4.1 step 3: ProjectMenu -> **Network Information Query > Vendor Country Info** is how you
  check that the vendor/country matches the package.
- `ReleaseDoc/.../Verify_Table_MC.xls` carries the build's component versions (FASTBOOTVER
  `Chipset-dallas 8.0.0.001(02AW)`, BOOTVER `System 8.0.0.046(09B4)`, PRODCOMPVER
  `Product-Anne 8.0.0.5`, CUSTCOMPVER `Cust-635000 8.0.0.1(000E)`, VERCOMPVER
  `Version-ANE-L22J-635000 8.0.0.1(000S)`, DATAVER `ANE-LX2J 8.0.0.110(C635)_DATA_ANE-L22J_hw_jp`).
- The 9.1 package family (e.g. the ANE-LX1 `9.1.0.132(C432E5R1P7T8)` service ROM on
  service-gsm.net) contains `ReleaseDoc/.../Rollback Guideline EMUI 9.0 Android 9.0 Rollback to
  EMUI 8.X Android 8.0 Operation Instruction_2019.1.23.doc` - **Huawei ships an official rollback
  procedure with the 9.1 service ROM.** Finding that document (currently behind a paid
  membership) is the highest-value lead left for the downgrade.

### The actual compatibility check, found by reading update-binary's strings

The failure message the device prints comes from `update-binary` inside `update_sd.zip`. That
binary is an aarch64 static ELF (2.9 MB, stripped) built from
`vendor/huawei/chipset_common/modules/hwrecovery/dload/huawei_update_binary/*.cpp`. Its strings
name the check outright:

    sec_dld_main_version_check
    "%s,line=%d: current version in oeminfo is %s"
    "ro.build.display.id"            + "%s,line=%d: ro.build.display.id is %s"
    "%s,line=%d: SDLOG: OEMINFO_AMSS_VER_TYPE read error,not allow update!"
    "%s,line=%d: version check fail,exit update!"
    "SOFTWARE_VER_LIST.mbn"
    OEMSBL_VERLIST / AMSS_VERLIST / VERLIST
    "OEMINFO is changed,update is unallowed!"

So the decision is: **package's `SOFTWARE_VER_LIST.mbn` vs the device's `ro.build.display.id`**
(plus oeminfo's AMSS version). `ro.build.display.id` on this unit is
`ANE-LX2J 9.1.0.132(C635E4R1P1)` and the package's list held only

    ANNEC00B000          <- "ANNE, cust C00, build B000" = factory/neutral state
    ANE-BD 1.0.0.1
    ANE-BD 1.0.0.999

hence "Incompatibility with current version".

Package layout (all ten entries; small metadata is plain text):

| entry | bytes | contents |
|---|---|---|
| `SD_update.tag` | 19 | `SD_PACKAGE_MIANPKG` (Huawei's own typo) |
| `full_mainpkg.tag` | 8 | `fullpkg` |
| `META-INF/com/google/android/updater-script` | 51 | `assert(compress_sd_update_from_zip("UPDATE.APP"));` |
| `SOFTWARE_VER_LIST.mbn` | 45 | the compatibility list above |
| `UPDATE.APP` | 4,340,264,812 | the firmware image (kept signed) |
| `update-binary` | 2,929,544 | the checker itself |

**Patch technique (used, and the payloads verified byte-identical afterwards):** rewrite the zip
with `zipfile` streaming `UPDATE.APP` straight through, appending the device's own version strings
to `SOFTWARE_VER_LIST.mbn`. Additions used: `ANE-LX2J 9.1.0.132(C635E4R1P1)`,
`9.1.0.132(C635E4R1P1)`, `C635E4R1P1`. The inner customized package
(`dload/ANE-L22J_hw_jp/update_sd_ANE-L22J_hw_jp.zip`, entry `update_ANE-L22J_hw_jp.app`) carries an
**identical** `SOFTWARE_VER_LIST.mbn`, so patch both or you waste a device cycle.

Scripts: `~/dev/p20-root/build_patched_zip.py`, `build_patched_inner.py`, `push_both.sh`,
`push_inner.sh`, `fb_verlist.sh`, `fb_oeminfo.sh`.

**Transfer without pulling the card:** the SD is reachable over adb while Android runs -
`/storage/D4DD-4FB0/dload/`. `adb push` into it works (2 GB at ~33 MB/s, ~60 s) and the md5 on the
device matched the host. Shell can `rm`/create in that directory even though the files are
root-owned with mode 711.

Still-unknown risk to state before letting it flash: this bypasses the version gate on a genuine
9.1 -> 8.0 downgrade on Kirin 659, and anti-rollback behaviour there is undocumented.

### Result of the SOFTWARE_VER_LIST.mbn patch, and the JAR digest formulas

First attempt - append the device's version strings to `SOFTWARE_VER_LIST.mbn`, rebuild the zip,
leave `MANIFEST.MF`/`CERT.SF` untouched:

* The version check **passed**: the updater moved into the write phase and a progress bar
  appeared, where the unmodified package had shown `Software install failed!` immediately.
* It then **aborted at 5%** - screen went dark, device rebooted, **no error text at all**, and the
  device came back on the same build (`9.1.0.132` / kernel `4.9.148`).

The silent abort is the signature of an `assert()` failure, and the package's entire
`updater-script` is one line:

    assert(compress_sd_update_from_zip("UPDATE.APP"));

`SOFTWARE_VER_LIST.mbn` **is** covered by the package signature - it appears in both
`MANIFEST.MF` and `CERT.SF`. But the version check *read our edited copy and passed*, so signature
verification is not what runs first; there is a later verification stage, and that is what 5% is.

**The JAR digest formulas, derived empirically** (match the original package's own known-good
values, `derive_digest.py`):

    MANIFEST.MF entry digest = base64(sha1(<entry payload bytes>))
    CERT.SF entry digest     = base64(sha1(<manifest section bytes> + CRLF CRLF))
    SHA1-Digest-Manifest     = base64(sha1(<entire MANIFEST.MF bytes>))

Two traps that cost a cycle each:

1. **These are base64 of SHA1, not hex.** `sha1sum` output is not what goes in the file.
2. **`CERT.SF`'s per-entry digest includes the blank separator line** after the manifest section
   (`...SHA1-Digest: <b64>\r\n\r\n`). Hashes computed on the section without that trailing CRLF CRLF
   do not match.

**Do not re-serialise a JAR manifest.** Rebuilding `MANIFEST.MF` from parsed sections silently drops
the blank lines between entries (539 -> 525 bytes here), producing a malformed manifest. Substitute
only the 32-character base64 digest values **in place**, byte-for-byte everywhere else; assert the
file length is unchanged afterwards.

`CERT.RSA` is Huawei's RSA signature over `CERT.SF` and cannot be reproduced. So the patched
package only works if the later check is digest-based rather than a strict signature verification.
Scripts: `build_patched_zip.py` (v1, incomplete), `build_patched_v3.py` / `build_patched_v3_both.py`
(in-place substitution, with consistency self-checks), `derive_digest.py`, `check_manifest.py`.

### The real mechanism: signature in the ZIP comment, and CVE-2021-40045

Source: taszk.io labs, "CVE-2021-40045: Huawei Recovery Update Zip Signature Verification Bypass"
(<https://labs.taszk.io/blog/post/75_hw_eocd_sig/>), plus "REUnziP" (FaultyUSB). Fixed by Huawei in
February 2022, so a 2018-era EMUI 9.1 recovery is very likely still vulnerable.

Key facts from that work:

* **The signature is stored in the ZIP comment section**, by increasing the EOCD's comment size and
  appending the signature to the end of the file. Measured on our package: EOCD at `0x7b14539b` with
  `comment_len=1579`, and the comment begins `b'signed by SignApk\x00'` followed by a PKCS#7 blob.
* The verifier parses the **first** EOCD; `minzip`, the extractor, walks **backwards** from the end
  and finds the **last** EOCD. "when the smuggled data contains an EOCD header, minzip would find
  that, as it comes after the EOCD of the original content, but the verification function still
  uses the original EOCD entry."
* Semantic checks are "trivially bypassed by including or omitting certain files":
  `IsSdRootPackage` <- `OTA_update.tag`, and `is_unauth_pkg` <- a `skipauth_pkg.tag` file.
  `SOFTWARE_VER_LIST.mbn` is still needed to be correct, so it has to be smuggled rather than omitted.
* `hw_update_pre_check` / `huawei_erecovery_pre_check`, `EreInstallPkg`, `do_ota_update`,
  `install_package` are the surrounding function names.

**The construction that was built and verified** (`build_eocd_both.py`):

    [ original ZIP: local headers, data, central directory ][ EOCD ][ comment ]
        comment = [ original "signed by SignApk" PKCS#7 block ][ smuggled ZIP ]

A ZIP central directory entry records the **absolute file offset** of its local header, so the
smuggled directory can point at the ORIGINAL local headers for every untouched entry - UPDATE.APP
included - and only needs one new local header for the changed file. **Growth was 836 bytes, not a
second 2 GB copy**, which also sidesteps the FAT32 single-file limit that a naive double-package
would have hit (2.06 + 2.06 GB > 4 GB).

Two traps that cost a cycle each:

1. **`PK\x05\x06` is only four bytes and occurs by chance inside compressed payloads.** Finding
   "the first" or "the last" occurrence is wrong in general - a 503 MB package contains several. A
   genuine EOCD is the one satisfying `pos + 22 + comment_len == file_size`; enumerate candidates
   with that test and take the min (verifier's) and max (extractor's).
2. The central directory record is 46 bytes and needs **six** `H` fields before the three `I`s:
   `<IHHHHHHIIIHHHHHII` (sig, ver_made, ver_need, flags, method, mtime, mdate, crc, csize, usize,
   nlen, elen, clen, disk_start, iattr, eattr, doff). A central entry's offset points at the
   **local header**, so file data starts at `off + 30 + name_len + extra_len`.

Verification harness (`verify_eocd_package.py`): parse both views independently and assert
(1) the verifier's view yields the 45-byte original list, (2) the extractor's view yields the
108-byte patched one, (3) every byte before the first EOCD matches the original byte for byte,
(4) the original signature comment survives as a prefix, (5) every non-target entry resolves to
identical offsets/sizes/methods in both views. All five held for both packages.

Device-side facts from the same round:
* `normal_reset_type` in the `misc` partition takes `VolUpRecovery` / `ForceSdUpdate` / `VolUsbUpdate`.
  The 3-button combo sets `VolUpRecovery`; the ProjectMenu "Software Upgrade > Memory card" path
  still runs the version check, so `ForceSdUpdate` is not what that path sets. Both paths refused the
  stock package identically with "Incompatibility with current version".
* Faster bootloader probing: 17 `oem` verbs at 20 s each overran a 420 s tool budget - batch smaller
  and keep the per-verb timeout short.

### Full version identity of the unit (readable without root)

Captured while the device ran Android 9.1.0.132. Useful because it shows the naming scheme
`SOFTWARE_VER_LIST.mbn` entries belong to, and because it gives the anti-rollback counter.

    ro.build.display.id                = ANE-LX2J 9.1.0.132(C635E4R1P1)
    ro.build.fingerprint               = HUAWEI/ANE-LX2J/HWANE:9/HUAWEIANE-LX2J/132C635R1:user/release-keys
    ro.build.version.incremental       = 132C635R1
    ro.build.version.emui              = EmotionUI_9.1.0
    ro.build.description               = ANE-L22J-user 9.1.0 HUAWEIANE-L22J 132-LGRP2-OVS release-keys
    ro.build.id                        = HUAWEIANE-LX2J
    ro.comp.hl.product_base_version    = ANE-LGRP2-OVS 9.1.0.132
    ro.comp.hl.product_cust_version    = ANE-LX2J-CUST 9.1.0.4(C635)
    ro.comp.hl.product_preload_version = ANE-LX2J-PRELOAD 9.1.0.1(C635R1)
    ro.comp.product_version            = Product-ANE-LGRP2-OVS 9.1.0(0000)
    ro.comp.system_version             = System 9.1.0.040(02EZ)
    ro.comp.version_version            = Version-ANE-L22J-635000 9.1.0(0008)
    ro.comp.cust_version               = Cust-OVS 9.0.0.1(0000)
    ro.board.boardname / boardid / modemid = ANE_LX2J_VG / 4990 / 3b691c00
    ro.product.CustCVersion            = C635
    ro.product.hardwareversion         = HL3ANNEM
    ro.boot.vercnt1                    = 0        <- anti-rollback version counter
    ro.boot.avb_version                = 0.0

`Version-ANE-L22J-635000 ...` is the same component-naming family that the package's own
ReleaseDoc verify table uses (`VERCOMPVER = Version-ANE-L22J-635000 8.0.0.1(000S)`), which is what
`ANNEC00B000` in `SOFTWARE_VER_LIST.mbn` abbreviates. Nothing here is writable from shell, and
`oeminforead-AMSS_VER_TYPE` / `OEMSBL_VERLIST` are not exposed over fastboot.

### 5% wall: three different package modifications, identical outcome

All three attempts produced the same result - progress bar, stop at 5%, screen dark, silent reboot,
device back on 9.1.0.132 with kernel 4.9.148 and no error text:

| attempt | what it changed | outcome |
|---|---|---|
| v1 | appended the device's version strings to `SOFTWARE_VER_LIST.mbn` (signature left broken) | 5% |
| v3 | same, plus `MANIFEST.MF` / `CERT.SF` digests recomputed so they are self-consistent | 5% |
| EOCD | signature fully preserved (original comment untouched), only the extractor's view patched | 5% |

The third one is the informative one: the verifier's view is byte-identical to the signed original
and the extractor's view carries the patched list, so both the signature check and the version check
should be satisfied. It still stops at 5%. Therefore **the 5% abort is not the package signature
check and not the version list**. Plausible remaining causes, none of which are addressable by
editing the package:

* a whole-package CRC that any modification breaks (the package does contain `sec_dld_crc_verify`
  and `update_comm_write_crc` machinery), and
* hardware/anti-rollback refusal at the first partition write.

Since satisfying the version gate *requires* modifying the package, and every modification lands on
the same 5% wall, **the free downgrade route is closed**. The device never shows an error for these
silent aborts - unlike the stock package's immediate "Incompatibility with current version" screen.

### Attempt 4: byte-exact same-size rebuild (also stopped at 5% - see the result section below)

Every earlier attempt changed the total file size, which matters if any check covers the whole
container (`sec_dld_crc_verify`, `update_comm_write_crc`). This build makes the size identical
while still patching the version list.

Recipe (`build_samesize2.py`, verified by `verify_samesize_both.py`):

1. Hand-write the ZIP so compression can be chosen per entry. zopfli (`pip install zopfli` in a
   venv) compresses the small entries; zopfli emits a zlib stream, so strip 2 bytes of header and
   4 bytes of adler to get raw deflate for the ZIP.
2. **Copy the big payload's compressed stream verbatim** (`UPDATE.APP` / `update_ANE-L22J_hw_jp.app`).
   Two reasons: it keeps the entry provably byte-identical, and recompressing it at level 9 shrinks
   it by ~5 MB, which then no longer fits the EOCD's **16-bit** comment-length field.
3. Patch `SOFTWARE_VER_LIST.mbn` and recompute the `MANIFEST.MF` / `CERT.SF` digests (the three
   formulas derived earlier).
4. Append the ORIGINAL signature comment verbatim as the start of the new comment, then pad with
   zeros so `body + comment == original size` exactly.

Result: sizes match the originals byte for byte (2,064,931,292 and 503,201,396); the original
signature comment survives as the comment prefix; digests recompute; payloads are identical.
Comment grew 1,579 -> 47,923 (main) and 1,579 -> 47,931 (inner), i.e. ~46 KB of zopfli padding.

Traps found while building this:

* **The EOCD comment length is 16 bits.** If the rebuilt body is *more* than 65,535 bytes smaller
  than the original there is no way to pad the comment up to the target - which is exactly what
  happens when the multi-GB payload is recompressed. Copying the original stream avoids it.
* **Huawei puts the ZIP64 field in the CENTRAL directory only.** `UPDATE.APP` (4,340,264,812 bytes
  uncompressed) has a 12-byte `0x0001` extra in the central record and **none** in its local header.
  Mirror that; do not "fix" it.
* Byte-identical rebuild checklist that passed: identical total size, patched list visible, original
  comment present as prefix, all three digests recompute, every original entry still present, and
  the big payload's md5 unchanged (`2c1da54e3e89782dd6fb72be8b7dda4e` for UPDATE.APP).
* Python detail: slices of a `bytearray` are `bytearray`, so a dict keyed on entry names needs
  `bytes(...)` first.

See also the attempt-3 section above: the EOCD-confusion package preserved the signature and still
stopped at 5%, so a size/whole-file check is the remaining package-side hypothesis.

### Attempt 4 result, and the correction it forces

The byte-exact same-size rebuild - identical total byte count, original signature comment preserved
as the comment prefix, digests recomputed, payloads byte-identical, md5-proven on the device - **also
stopped at 5%**, exactly like the other three. Four different package modifications, one outcome:

| attempt | what it changed | outcome |
|---|---|---|
| v1 | version list appended (signature left broken) | 5%, silent reboot |
| v3 | + `MANIFEST.MF`/`CERT.SF` digests recomputed | 5% |
| EOCD | signature fully preserved, only the extractor's view patched | 5% |
| same-size | total byte count identical to the original | 5% |

**Ruled out on this device by those four:** total file size, JAR digests, the comment signature, and
the *display-string* form of the version list. What remains is either a check that depends on none
of those, or something on the device side of the boundary.

There is a public precedent for the symptom - an ANE-LX1 user on XDA: "verify goes 5% then 6% then
back to 5%, then 6% then shows 'install failed'". So ~5% is the **verification** stage, not a
partition write, which matches the silent abort with no error screen here.

### Reading the vendor's own check code (what replaced guessing)

Recipe in `references/firmware-package-forensics.md`. Applied to the package we already had it
yielded `sbin/recovery` (3,969,400 bytes), and its strings name the checks directly:

    SOFTWARE_VER_LIST.mbn   + "file found!" / "file is not exist!"
    SD_update.tag
    skipauth_pkg.tag        + "skip update auth file found!"
    verify_update_auth
    "No need to auth for sdupdate or usbupdate!"
    "No need to auth for data or public package!"
    VERSION.mbn             + /data/VERSION.mbn
    update_%s_%s.zip / update_full_%s_%s.zip

Two earlier hypotheses died on that evidence:

* **`VERSION.mbn` and `skipauth_pkg.tag` are NOT required here.** The recovery says verbatim
  "No need to auth for sdupdate or usbupdate!" - an SD update skips auth entirely. The missing-auth-file
  theory is dead.
* **The 2022-era tree does not exist in this recovery.** `BOARDID_LIST.mbn`, `packageinfo.mbn`,
  `sec_xloader_header`, `UPT_VER.tag` and `hotakey_sign_version.tag` have **zero** occurrences. Do not
  carry the UnZiploc/REUnziP file requirements onto a 2018 device.

Also worth keeping: `update-binary` itself knows only `SD_update.tag` and `full_mainpkg.tag`, so the
pre-checks are recovery-side and `update-binary` runs last. And the recovery ramdisk carries its own
embedded package at `dload/update_huawei_dload.zip` (1,170,046 B) whose `META-INF/com/android/metadata`
is a file our TA build does not have - the TA/factory packaging difference shows up here too.

### The version list's real format - the hypothesis attempt 5 tests

`ANNEC00B000` decomposes as `<MODEL><CUST>B<BUILD>` = **ANNE + C00 + B000**, the factory/neutral
state. This unit is **ANNE + C635 + B132**. Every earlier attempt appended the *display* string
(`ANE-LX2J 9.1.0.132(C635E4R1P1)`), which is not that shape at all.

Attempt 5 (`~/dev/p20-root/build_samesize3.py`, output `firmware/custfix/`) replaces that first line
with both candidate forms and leaves everything else as in attempt 4:

    ANNEC635B132      <- this unit's exact build
    ANNEC635B000      <- base build, in case the test is >= rather than ==
    ANE-BD 1.0.0.1
    ANE-BD 1.0.0.999

`ANNEC635B132` is one byte longer than `ANNEC00B000`; the same-size recipe absorbs that in the
comment padding. Sizes verified identical to the originals, digests recomputed, payloads
byte-identical, pushed to the SD. **Status at session end: built and staged, not yet device-tested.**
If it also stops at 5%, the list's form is not the wall either.

### What people who hit the same wall actually did (XDA precedents, checked 2026-10)

XDA thread 3881779 ("My complete bootloader unlock and root guide", brugernavn, Dec 2018; 3k replies)
is the canonical ANE guide. Reading it end to end answers the question directly.

**Post #1 (2018)** - the original recipe: "Then you need to downgrade your firmware to 146 using Dload
method, as DCU Client can't read the bootloader unlock code on newer firmwares." Package used:
`8.0.0.146(C432)`. Route: `*#*#2846579#*#*` -> Software Upgrade -> SdCard Upgrade. This worked in
2018 **because those units were already on EMUI 8** - it is not a 9.1 downgrade.

**Post #143, -Alf- (the ANE authority), Sep 2021:**

> You have to downgrade to EMUI 8 **via HiSuite**, and then downgrade via dload method to the lower
> build number with google's security patch April - June 2018. (e.g. ANE-LX3 8.0.0.120 (C771).
> Use only firmware (C771)! (C771) is your device's regional variant. ... (Any forced flash with
> wrong region, e.g. C432, C605 etc., may brick your phone!)

**Post #147, -Alf- (the operative detail):**

> First of all, make sure you have **the option to downgrade to Oreo in HiSuite**. If the rollback
> option is not available with your HiSuite ("switch to the older version" or "earlier version"),
> you must downgrade to the **lower Pie build version number doing the dload method (flashing
> Service ROM)**.

So the downgrade is stepwise and only the last step is dload: 9.1 -> lower EMUI 9 (dload a service
ROM) -> EMUI 8 (HiSuite) -> lower 8.0.x (dload). The "downgrade one by one" folklore we found
earlier at Stack Exchange is a garbled version of exactly this.

**Confirmed working in 2021, on this device family:**
* Gladiator00, ANE-LX2 on `9.1.0.353(ZAFC185E4R1P8)`, Sep 11 2021: "**HiSuite is downgrading to
  ANE-LX2 8.0.0.0.152**" - HiSuite offered the rollback and performed the 9 -> 8 step.
* paulpr7, Sep 2021: "I did what you told me using **HiSuite**, and then I used a C605 firmware on
  my phone, which had a C771 firmware and **it worked fine**! ... I managed to downgrade and get the
  bootloader unlock code. **In the end I was able to unlock it**". (A cust mismatch worked in that
  one case; -Alf- still warns against forced cross-region flashes.)

**Conclusion for our unit:** dload-only cannot cross the EMUI 9 -> 8 boundary - our seven measured
routes plus this thread agree. HiSuite's "switch to an older version" is the missing step, and
HiSuite is free; it needs Windows (a VM is fine) and Huawei's servers still answering for the
device. After reaching EMUI 8 the rest is the documented path (dload to the April-June 2018 patch
level, then a code-reading tool).

Note also the warning that a forced flash of the wrong regional variant (C432/C605 on a C635 unit)
risks a brick, so any cross-cust attempt must stay within the frankenZIP route rather than a plain
dload of a foreign package.

### THE MISSING STEP: HiSuite offers the EMUI 8 rollback only from an EARLY EMUI 9 build

Source: XDA "[TUTORIAL] Downgrading to EMUI 8 using HiSuite" (huawei-p-smart forum, thread t4064605),
plus -Alf-'s posts quoted above. The mechanism is Huawei-wide, not model specific.

The tutorial's operative paragraph, verbatim:

> Place the dload folder in the root directory of your SD Card ... hold both volume buttons while
> powering on to engage Force Update ... Connect the phone via usb and choose file transfer ...
> Click Update and now bottom right of the window it should ask you for older version so click on it
> and it will present you with going back to EMUI 8. **(Explanation: I figured out if you run the
> latest version of EMUI 9 HiSuite will not present you a older version button ... so that's why
> you downloaded the very first EMUI 9 build where it lets you do it)**

So the complete path is:

    1. dload down to the FIRST/earliest EMUI 9 build for the device   <- dload, works
    2. connect to HiSuite; only from such an early 9 build does the UI offer
       "switch to an older version"
    3. HiSuite then performs the EMUI 9 -> EMUI 8 rollback itself (free, Windows)
    4. from EMUI 8, further dload steps down to the April-June 2018 patch level
    5. then a code-reading tool for the bootloader unlock code

This is what -Alf- meant by "downgrade to the lower Pie build version number doing the dload method
(flashing Service ROM)". Our unit is on **9.1.0.132**, i.e. an early 9.1 build, so it plausibly
already satisfies step 1 - the check is simply whether HiSuite shows the option.

The tutorial's first step used an **EMUI 9.0.1** service ROM (`FIG-LX1 ... 9.1.0.115(C432E5R1P3T8)
Firmware 9.0.0 r3 EMUI9.0.1`), consistent with "service ROM" being the type that works for dload
steps, versus the TA/factory build we hold.

Strengthening option if HiSuite refuses to show the option: **HiSuite-Proxy**
(github.com/ProfessorJTJ/HISuite-Proxy, archived Aug 2023 but downloadable). It patches HiSuite's
`httpcomponent.dll`, runs a local proxy on 127.0.0.1:7777, and lets you feed HiSuite specific ROMs
("Support for Roll back ROMs (kind of full ROM)"). It also documents the ROM-side requirements:
CUST & PRELOAD versions must match what the device reports under
`*#*#2846579#*#*` -> Version Information, ROM IDs and dates should be consistent, and downgrades
should proceed in **incremental** BASE steps (.211 -> .210 -> .209, not a jump). A mismatch produces
exactly the "Software Install Failed" we have been seeing.

Environment requirement: Windows (a VM with USB passthrough is fine). HUAWEI's own support text
confirms the rollback option appears only "when the current system can be rolled back".

### Environment: Windows required, Wine is ruled out by measurement

HiSuite cannot be used from Linux. Two independent sources:
* WineHQ bugzilla **bug #51666 "HiSuite cannot find phone"** (filed 2023-07-25, still unconfirmed/
  open). HiSuite installs and runs under Wine but never enumerates the device, because it talks to
  the phone through a Windows kernel driver, which Wine cannot load. There is no workaround.
* XDA (rollback thread 4044711): "Tested HiSuite on Linux emulated via Wine. I was able to use the
  Huawei tool but I couldn't hook up the mobile to the app."

So the dual-boot Windows install is the route. A USB-passthrough VM works too, but native Windows
is the safer bet for driver enumeration.

Useful detail found on this machine: **the phone itself exposes a virtual CD-ROM**
(`/media/$USER/HiSuite`, iso9660, 3.7 MB) containing `HiSuiteDownLoader.exe` (2016-04-20 build) plus
`Autorun.inf` and `Document/`. That is a fallback installer if the current one will not connect.

Official installer, downloaded and verified from
`https://consumer-tkb.huawei.com/weknow/servlet/download/public?contextNo=W00018218`
(65,412,392 bytes, PE32 Nullsoft Installer; md5 `09b8fc035d8bb61b1d591f6ad9a64246`).

**Both HiSuite generations were obtained, and the older one is the interesting one.** The second
context number `W00003542` returns a 38,007,763-byte zip whose single payload is
`HiSuite_10.0.0.510_OVE.exe` (38,027,648 bytes, md5 `a487666dfe217cef1ef97c9c44e38698`, plus a
490-byte `.asc` GPG signature). HiSuite Proxy's own guide recommends **10.0 / 10.1 / 11.0**, and the
XDA downgrade tutorial was written against that era of HiSuite, so 10.0.0.510 is exactly the
recommended generation for a 2018-2019 device. Both installers were staged on Windows: try the
current one first, fall back to 10.0.0.510 if it will not connect or offers no rollback.

Downloaded copies plus
HiSuite Proxy V3.3.0 and a step-by-step Japanese checklist were placed at
`C:\P20Lite-unlock\` on the Windows partition. Note the NTFS volume mounts with the Windows ACLs
honoured, so `Users/mikop/Downloads` is not writable from Linux but the volume root is - place
staged files at the root.

### BREAKTHROUGH 2026-10-01: HiSuite downgrade worked, root achieved, unlock path identified

**HiSuite performed the EMUI 9 -> 8 step.** Dual-boot Windows, HiSuite installed from the staged
`C:\P20Lite-unlock\`, device in HiSuite mode (`*#*#2846579#*#*` -> Background Settings -> USB Port
Settings -> HiSuite), HDB allowed. Result: **`ANE-LX2J 8.0.0.151(C635)`, Android 8.0.0, SDK 26,
kernel `4.4.23+`** (`#1 SMP PREEMPT Fri Mar 1 00:11:18 CST 2019`). Note HiSuite gave **8.0.0.151**,
not the 8.0.0.110 we had been trying to dload. The seven dload routes were indeed a dead end; the
missing step was always HiSuite.

After the downgrade `/data` is wiped, so adb needs re-authorising. On EMUI 8 the phone only
advertises an ADB interface when **USB debugging is on in developer options** *and* the USB port
mode allows it - plain "file transfer" alone leaves the interface list at `MTP + Mass Storage`.
Check with `lsusb -v -d 12d1:107e | grep iInterface`; you want `ADB Interface` present.

**Root: CVE-2019-2215 works on this build.** `cve-2019-2215` as built for 4.4.23 (STRUCT_CRED_OFFSET
0x618) got `uid=0(root)` on the first run, ~20s. `/dev/binder` is `crw-rw-rw-` so the UAF is
reachable from the `shell` user.

**Critical operational detail - the UAF needs a clean heap.** The first run after a boot succeeds.
Subsequent runs die silently right after `[>] Overwrite addr_limit with 0xfffffffffffffffe` and leave
**zombie** `[cve-2019-2215]` processes; you never see `[+] struct_cred is at:`. So: **reboot before
each real attempt** and re-run once (not in a loop). Diagnose with
`adb shell 'ps -A | grep cve'` - `Z` entries mean earlier runs died there.

**SELinux bypass fails on this build - patched.** The upstream flow calls `live_with_selinux()`, which
loads `/sys/fs/selinux/policy`, makes every type permissive and writes it back. On this device that
file is unreadable from the `shell` domain (`Can't open '/sys/fs/selinux/policy': Permission
Denied`, twice), so the rewrite never happens and the process stays `u:r:shell:s0`. The AVC-cache
fallback also misses because `AVC_CACHE 0xffffff800a2d4c40` (and the other static addresses) quote a
different kernel build; the exploit's own `set_sid()` in `dac.c` is dead code and carries the comment
"doesn't work". Patch applied in this workspace: `set_sid(cred_addr, 1)` before the existing calls
(`KERNEL_DOMAIN_SID 1ul` in `kernel_specific.h`), i.e. move our own cred into the initial `kernel`
SID, from which the policy file becomes readable and the permissive rewrite can proceed. Note the
root shell *without* that fix is uid 0 **but domain shell:s0** - `blockdev` on `/dev/block/...`
returns Permission denied, so partition access needs the bypass.

### The unlock itself: nvme partition + hisi-nve

Sources: the Kirin AOSP cheat sheet (gist A2L5E0X1) and R0rt1z2/hisi-nve README:

> The unlock "flag" is basically in the **nvme** partition ... It allows you to do **everything** in
> fastboot. ... `fastboot oem hwdog certify set 0` ... or also using the nvme tool by @R0rt1z2
>
> nvme: contains device infos like SN, macs, **unlock code**, etc. **DO NOT TOUCH!!**

-Alf- on the ANE family: "This lock is controlled (at least on ANE and LLD models) using the command
`fastboot oem hwdog certify set <0 or 1>`", and a user confirms `hwdog certify close` did relock
their bootloader even though it did not persist across reboots (so the command flips the live state,
the stored flag is what needs editing).

`hisi-nve` (github.com/R0rt1z2/hisi-nve, built here at /home/placeless/dev/hisi-nve) is the tool.
It supports **hi6250** explicitly (380 entries in `nve_mappings.h`, including FBLOCK, USRKEY,
ADBLOCK, BOOTCTL). Usage: `hisi-nve <read|write> <key> [value] [nvme.img]`. It prefers the driver
node **`/dev/nve0`** with ioctl `NVME_IOCTL_ACCESS_DATA` (`_IOWR('M', 25, ...)`), which is much safer
than writing the raw partition; it falls back to opening the partition, then to an image file.
It hashes the value with SHA-256 for `USRKEY` (16 bytes) - matching PotatoNV's note that the unlock
key can be rewritten as the SHA-256 of a chosen key. `FBLOCK` is a **1-byte** value (the source
special-cases it). README: "always backup NVME".

Two proven recipes from the tool's README:

    # set our own unlock code, then use it in fastboot
    hisi-nve w USRKEY 0123456789ABCDEF
    reboot bootloader ; fastboot oem unlock 0123456789ABCDEF   # factory reset, then UNLOCKED

    # or flip the lock flag directly
    hisi-nve r FBLOCK        # prints FBLOCK 0..6 with values
    hisi-nve w FBLOCK 0
    rebuild ; fastboot oem lock-state info   # FB LockState / USER LockState: UNLOCKED

Build fixes needed for NDK 28 (same family as the PAGE_SIZE problem): `sha256.c` includes
`<memory.h>`, which Bionic does not provide `memset` from - change to `<string.h>`.

Other facts from the cheat sheet worth keeping: partition layout and names (`xloader`, `fastboot`,
`nvme`, `oeminfo`, `splash2` logs, `modem_*`); `xloader` erase gets you into USB SER/testpoint mode;
EMUI 8 splits boot into `kernel`/`ramdisk`/`recovery_ramdisk`/`recovery_vendor` with real offsets;
pstore is the only kernel-log route (last_kmsg does not exist); bootloader logs at
`/proc/balong/log`.

### 2026-10-02: root is real, SELinux is the wall, and the bypass was aimed at the wrong memory

**Root is reproducible.** The 4.4.23 port gives `uid=0(root)` plus every capability on
`ANE-LX2J 8.0.0.151(C635)`; a winning run takes about 2 s.

**SELinux still owns the block devices.** With uid=0 and all caps:

    dd if=/dev/block/bootdevice/by-name/nvme of=...          -> Permission denied
    dd if=/dev/block/bootdevice/by-name/kernel of=...        -> Permission denied
    blockdev --getsize64 /dev/block/bootdevice/by-name/nvme  -> Permission denied
    ls -laZ /dev/nve0   ->  crwxrwx--- root system u:object_r:recovery_device:s0
    echo 0 > /sys/fs/selinux/enforce                         -> write exits 1
    setenforce 0                                             -> Invalid argument
    cat /proc/self/attr/current                              -> u:r:shell:s0
    /proc/kallsyms                                           -> every address 0000000000000000

DAC is bypassed (root + CAP_DAC_OVERRIDE), so each denial above is type enforcement. There is no
capability-only escape, however tempting the capabilities look. `hisi-nve` run from such a process
prints `[!] ioctl mode not available, will use file mode!` and then `[-] Unable to open nvme.img!`.

Device nodes: `/dev/block/bootdevice/by-name/` (and `/dev/block/platform/hi_mci.0/by-name/`),
`nvme -> mmcblk0p7`, `oeminfo -> mmcblk0p8`, `kernel -> mmcblk0p30`.

**Why the bypass did nothing — the two constants disagree by different amounts.** Symbols recovered
from the 8.0.0.110(C635) KERNEL block:

    fair_sched_class   0xffffff8008f48408      exploit has 0xffffff8008f78408  (+0x30000)
    avc_cache          0xffffff800a276c40      exploit has 0xffffff800a2d4c40  (+0x5E000)

get_kaslr_offset() is `read(task+0x88) - FAIR_SCHED_CLASS`, so the slide came out 0x30000 low, and
`avc_cache_addr = slide + AVC_CACHE` then missed by -0x30000 + 0x5E000 = **+0x2E000 (188 KB)**. The
bypass was not inert; it wrote 188 KB past the AV cache on every run, and the device survived. Note
this also means the cred-SID idea (set the cred's SID to the initial kernel SID 1) was aimed at a
different problem — with the addresses corrected the upstream flow should work as designed.

**UPDATE.APP block inventory, 8.0.0.110(C635)** — 32 headers, magic `55 aa 5a a5`, so any of these
can be cut straight out of the extracted file:

    [ 0] @0x000000005c SHA256RSA          hdr=100    size=         256
    [ 1] @0x00000001c0 CRC                hdr=228    size=     264,792
    [ 2] @0x0000040cfc CURVER             hdr=100    size=          16
    [ 3] @0x0000040d70 VERLIST            hdr=100    size=          45
    [ 4] @0x0000040e04 PACKAGE_TYPE       hdr=100    size=          15
    [ 5] @0x0000040e78 EFI                hdr=108    size=      17,408
    [ 6] @0x00000452e4 XLOADER            hdr=134    size=      69,696
    [ 7] @0x00000563ac FW_LPM3            hdr=182    size=     168,064
    [ 8] @0x000007f4e4 FASTBOOT           hdr=1404   size=   2,672,640
    [ 9] @0x000030c260 MODEMNVM_UPDATE    hdr=9798   size=  19,865,474
    [10] @0x0001600828 TEEOS              hdr=1388   size=   2,638,080
    [11] @0x0001884e94 TRUSTFIRMWARE      hdr=156    size=     117,760
    [12] @0x00018a1b30 SENSORHUB          hdr=504    size=     830,784
    [13] @0x000196ca68 FW_HIFI            hdr=2592   size=   5,107,264
    [14] @0x0001e4c2c8 KERNEL             hdr=12386  size=  25,165,824
    [15] @0x000364f32c RAMDISK            hdr=8290   size=  16,777,216
    [16] @0x0004651390 RECOVERY_RAMDISK   hdr=16482  size=  33,554,432
    [17] @0x00066553f4 RECOVERY_VENDOR    hdr=8290   size=  16,777,216
    [18] @0x0007657458 ERECOVERY_KERNEL   hdr=12386  size=  25,165,824
    [19] @0x0008e5a4bc ERECOVERY_RAMDISK  hdr=16482  size=  33,554,432
    [20] @0x000ae5e520 ERECOVERY_VENDOR   hdr=8290   size=  16,777,216
    [21] @0x000be60584 RECOVERY_VBMETA    hdr=102    size=       7,104
    [22] @0x000be621ac ERECOVERY_VBMETA   hdr=102    size=       7,104
    [23] @0x000be63dd4 DTS                hdr=11886  size=  24,139,776
    [24] @0x000d56c444 MODEM_FW           hdr=49250  size= 100,663,296
    [25] @0x00135784a8 VBMETA             hdr=104    size=      10,176
    [26] @0x001357acd0 ODM                hdr=49862  size= 101,915,640
    [27] @0x00196b8b90 CACHE              hdr=3200   size=   6,348,948
    [28] @0x00d759140c CUST               hdr=4498   size=   9,007,396
    [29] @0x00f9b91768 VERSION            hdr=2312   size=   4,530,396
    [30] @0x00f9fe414c PRODUCT            hdr=59102  size= 120,837,656
    [31] @0x010132fe44 USERDATA           hdr=12388  size=  25,166,020

(There is no SYSTEM block here: the main images live in the inner
`update_sd_ANE-L22J_hw_jp.zip`, and this outer file carries the platform images.)

**The race is layout-sensitive — plan for it.** Measured repeatedly:

- The binary as originally built (DELAY 25 us) wins essentially every time once the system has
  settled; the first success came at ~10 minutes uptime, while failures clustered below 4 minutes.
- Every rebuild behaves differently, even from identical source: rebuilds of the same 96,552-byte
  result produced different md5 (so compare behaviour, never hashes), and rebuilt variants —
  including one with only the cred-SID patch added — died right after
  `[>] Overwrite addr_limit with 0xfffffffffffffffe` with no `[+] struct_cred is at:` line, leaving
  zombie `[cve-2019-2215]` processes. That is `check_addr_limit()` failing: the UAF itself lost,
  before any added code ran. The added code is therefore not the cause; layout is.
- Consequently: make DELAY readable from argv (`scripts/apply_runtime_delay.py`) so one build can
  sweep it, and sweep finely — a first pass over only 8 values was wasted effort.
- `adb shell 'ps -A | grep cve'` is the cheap diagnostic: `Z` entries mean earlier runs died at the
  addr_limit step, so reboot before a serious attempt.
- Patching the two constants in place inside the winning binary would preserve the timing exactly,
  but they are neither 8-byte literals in the file nor adjacent movz/movk sequences (both searched,
  neither found), so the patch point has to be read out of the disassembly around the
  `[+] @avc_cache=%lx` printf path. Not done yet — recorded so the next session does not repeat the
  search.

### Older route list

1. A **different, unpatched** local-root bug for a 4.9 kernel at a 2019-05 patch level
   (`CVE-2019-2181`, `CVE-2019-15666`, `CVE-2020-0041`, `CVE-2020-0423`, ...). Each needs the same
   kind of port; nothing is known-ready for this exact kernel.
2. **Paid client** (DC-Unlocker / HCU, ~EUR 4-5) - documented to drive exactly the manufacture-mode
   state this unit reaches; it holds the manufacture-mode AT password this device wants.
3. **Physical testpoint** (TP8->GND) - explicitly rejected by the user.
4. Huawei's official unlock portal - closed 24 May 2018.

## Host staging carried over

- `~/dev/potatonv` = PotatoNV-crossplatform with `bootloaders/hisi65x_a` populated from the
  Windows release zip (xloader @0x00020000, fastboot @0x10000000). Entry point `python -m usrlock`.
- `~/dev/huawei-unlock-tool` = partial C# source drop (werasik2aa). `DIAGNOS/DIAG.cs`
  `SW_PCUI_TODIAG()` = `AT$QCDMG=115200\r`; its DIAG side is **dongle-based**
  (`REWRITE_BOOTLOADER_KEYQC(key, donglename, dongledatarsaoraespksx)`, `AUTH_PHONE` -> `CCEE`,
  `READ_SECRET_KEY` -> `EDEE` replies `Please Auth`), so only its HISI half is relevant and that
  half is PotatoNV's, which needs VCOM.
- `~/dev/huawei-brute` = brute-force tool; **not viable** (walks the 16-digit space from
  1e15 with step `sqrt(IMEI)*1024`, ~2-4 s per attempt, reboot every 4 failures).
- `~/dev/usbtool-*.py` + `~/dev/usbtool-env` (pyusb) for PCUI/AT probing.
- FYI a naive `python -c "import fastboot"` check fails even with fastbootpy installed; verify by
  running the tool.
