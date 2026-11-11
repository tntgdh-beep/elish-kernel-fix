# [FIX] Xiaomi Pad 5 Pro (elish) — full system freeze with Chrome on LineageOS 24.0

**Applies to:** Xiaomi Pad 5 Pro (`elish`, M2105K81AC) running LineageOS 24.0
**Kernel:** 4.19.325-cip136-st20 (LineageOS/android_kernel_xiaomi_sm8250, commit `6b34d2476532`)

---

## TL;DR

The kernel that LineageOS 24.0 ships for `elish` is missing a cgroup freezer fix
that LineageOS already applied to other 4.19 devices (a52q / a72q / gta4l,
issue #756). Without it, opening Chrome can freeze the whole system until the
watchdog reboots the tablet.

I backported the fix, built a kernel and I'm running it. The patch touches a
single file and **does not change the kernel version string**, so the prebuilt
`vendor_dlkm` modules keep loading — no loss of Wi-Fi, GPU or touch.

- **Patch + build scripts:** https://github.com/tntgdh-beep/elish-kernel-fix
- **Prebuilt `boot.img`** (for build `24.0-20261013-UNOFFICIAL-elish`):
  https://github.com/tntgdh-beep/elish-kernel-fix/releases/tag/elish-24.0-20261013

---

## Symptoms

After some time using Chrome (easier to trigger with several tabs open), the
tablet freezes completely: touch stops responding, audio hangs, and a few
seconds later the device reboots by itself.

In `pstore` / last kernel log you'll find something like:

```
sysrq: Kill All Tasks
```

Sometimes instead of a reboot you just see the UI come back with `system_server`
restarted (soft reboot to the lockscreen).

If you have `pstore` access, you can check for the old crash:

```bash
adb root
adb shell grep -c "Kill All Tasks" /sys/fs/pstore/console-ramoops-0
```

## Root cause

The 4.19 kernel uses the cgroup v2 freezer to freeze cached processes. The
implementation in `cgroup_leave_frozen()` is outdated:

```c
	spin_unlock_irq(&css_set_lock);

	if (unlikely(current->frozen)) {
		/*
		 * If the task remained in the frozen state,
		 * make sure it won't reach userspace without
		 * entering the signal handling loop.
		 */
		spin_lock_irq(&current->sighand->siglock);
		recalc_sigpending();
		spin_unlock_irq(&current->sighand->siglock);
	}
```

When leaving the frozen state races with `vfork()` or `do_signal_stop()`, the
cgroup's `nr_frozen_tasks` counter and state can spuriously go to "unfrozen"
while the task is still logically frozen. That task never re-enters
`do_freezer_trap()`, so it is stuck forever, and the system hangs until the
hardware watchdog resets the device.

The fix is the upstream implementation, already present in
`LineageOS/android_kernel_qcom_sm8150` (lineage-20, commit `7a05073b`,
"UPSTREAM: cgroup: prevent spurious transition into non-frozen state"), but
**not** in `android_kernel_xiaomi_sm8250` (lineage-24.0) or
`android_kernel_qcom_sm8250` (lineage-20).

## What the patch does

It replaces the `recalc_sigpending()` block with `JOBCTL_TRAP_FREEZE` +
`TIF_SIGPENDING`:

```c
	} else if (!(current->jobctl & JOBCTL_TRAP_FREEZE)) {
		spin_lock(&current->sighand->siglock);
		current->jobctl |= JOBCTL_TRAP_FREEZE;
		set_thread_flag(TIF_SIGPENDING);
		spin_unlock(&current->sighand->siglock);
	}
```

This forces the task through `do_freezer_trap()` before it can return to
userspace, so the spurious "unfrozen" transition can no longer happen.

---

## Requirements

- **Unlocked bootloader** (`ro.boot.verifiedbootstate=orange`). The generated
  `boot.img` has no AVB signature, which is accepted on an unlocked device —
  same mechanism Magisk uses.
- `adb` + `fastboot` on your PC.
- Root on the tablet to back up the current boot partition (`adb root` on
  LineageOS userdebug builds, or Magisk's `su`).

## Option 1 — Flash the prebuilt boot image (5 minutes)

### 1.1 Check compatibility FIRST

```bash
adb shell getprop ro.lineage.version
# must be: 24.0-20261013-UNOFFICIAL-elish

adb shell uname -r
# must be: 4.19.325-cip136-st20-perf-g6b34d2476532
```

If your build is newer, **stop here** and use Option 2. Flashing a kernel built
from a different commit makes the `vendor_dlkm` modules fail to load (no Wi-Fi,
no GPU, no touch).

Also confirm your slot:

```bash
adb shell getprop ro.boot.slot_suffix
# _a or _b
```

The commands below use `boot_a`; replace with `boot_b` if your slot is `_b`.

### 1.2 Back up the current boot partition (do not skip)

```bash
adb root            # or use "su -c" with Magisk
adb shell dd if=/dev/block/by-name/boot_a of=/sdcard/boot_stock.img
adb pull /sdcard/boot_stock.img
```

Keep that file. It is your rollback.

### 1.3 Download and verify

Grab `boot_a_patched.img` from the releases page:

https://github.com/tntgdh-beep/elish-kernel-fix/releases/tag/elish-24.0-20261013

```
SHA256: fcdeffc333537e6317aefc9bae51c4f8e39ca02b280772c1e1c52760f6d3003e
Size:   55078912 bytes
```

### 1.4 Flash

```bash
adb reboot bootloader
fastboot devices
fastboot flash boot_a boot_a_patched.img
fastboot reboot
```

First boot takes the usual 30–60 s.

### 1.5 Verify

The kernel version string is intentionally unchanged, so check the build
timestamp instead:

```bash
adb shell uname -v
# must contain: #2 SMP PREEMPT Wed Nov 11 06:59:56 UTC 2026
```

And confirm the modules all loaded:

```bash
adb shell "dmesg | grep -iE 'version magic|disagrees about version|Unknown symbol'"
# should print nothing
```

### 1.6 Rollback (if anything goes wrong)

```bash
fastboot flash boot_a boot_stock.img
```

If it bootloops and you can't reach `adb`: hold **Volume Down + Power** to get
into fastboot, then run the command above.

## Option 2 — Build it yourself (recommended if your build is newer)

### 2.1 Install dependencies (Ubuntu / Debian host)

```bash
sudo apt install build-essential bc bison flex libssl-dev libelf-dev \
  python3 cpio rsync device-tree-compiler clang lld llvm curl
```

### 2.2 Build

```bash
git clone https://github.com/tntgdh-beep/elish-kernel-fix
cd elish-kernel-fix
./build-kernel.sh
```

The script downloads the kernel at commit `6b34d2476532`, applies the patch,
builds `Image`, and **aborts if the resulting version is not exactly**
`4.19.325-cip136-st20-perf-g6b34d2476532`.

Output: `elish-kernel/src/out/arch/arm64/boot/Image`

> If the final link runs out of memory, lower the parallelism:
> `JOBS=4 ./build-kernel.sh`

### 2.3 Pack the boot image

```bash
# dump the stock boot from the tablet (root required)
adb root
adb shell dd if=/dev/block/by-name/boot_a of=/sdcard/boot_stock.img
adb pull /sdcard/boot_stock.img

python3 repack.py --stock boot_stock.img \
                  --image elish-kernel/src/out/arch/arm64/boot/Image \
                  --output boot_a_patched.img
```

`repack.py` replaces **only the kernel** — ramdisk, `os_version` and
`os_patch_level` are kept from the stock image, and it re-reads the result to
make sure it's correct. Then flash it as in 1.4.

## Option 3 — Integrate into your own LineageOS build

```bash
cd kernel/xiaomi/sm8250
git am /path/to/0001-cgroup-freezer-prevent-spurious-transition.patch
```

The patch is in `git am` format (with `From:`, `Subject:` and
`Signed-off-by:`), so it also works with `patch -p1` from the build tree.

---

## How to verify the fix is actually active

`uname -r` will **not** change — that's intentional, it's what keeps the
prebuilt modules loadable. Two reliable checks:

1. Kernel build timestamp: `adb shell uname -v` shows the build date of the
   patched kernel (`#2 SMP PREEMPT Wed Nov 11 06:59:56 UTC 2026` for the
   prebuilt image).

2. Note: `cgroup_freezer_frozen_exit` still being in `/proc/kallsyms` is
   **expected**. It is removed by a *later* upstream commit (`28586903`), which
   is not part of this backport. What changes here is `cgroup_leave_frozen`,
   which no longer calls `recalc_sigpending()`.

## Troubleshooting

**Bootloop after flashing** — restore the backup:
`fastboot flash boot_a boot_stock.img`. Nothing else on the device was touched.

**No Wi-Fi / no touch / no GPU after booting** — you flashed an image built from
a different kernel commit. Restore the backup and rebuild with Option 2.
Check with:

```bash
adb shell "dmesg | grep -i 'version magic'"
```

**`adb root` says "adbd cannot run as root in production builds"** — use Magisk:
`adb shell su -c "dd if=/dev/block/by-name/boot_a of=/sdcard/boot_stock.img"`

**The freeze still happens** — this fix only addresses the cgroup freezer bug.
If your log shows a native `system_server` crash in BPF (tombstone with
`bpf`/`BPF_PROG_RUN` frames), that's a different bug and is not fixed here.

## FAQ

**Does it survive a LineageOS OTA?**
No. Every OTA overwrites the boot partition. After updating, flash the image
again — but only if the OTA's kernel is still commit `6b34d2476532`; otherwise
rebuild.

**Is it safe / does it break SafetyNet?**
Your bootloader is already unlocked and `verifiedbootstate` is already `orange`,
so this changes nothing about the device's attestation state. The image is the
stock ramdisk with a patched kernel.

**Does it change performance or battery?**
No. It doesn't touch the scheduler, the freezer on/off logic, or any tunable.
It only fixes a race in the frozen→unfrozen transition.

**Can I use it on another sm8250 device?**
Probably, but it was only tested on `elish`. Build it yourself with
`build-kernel.sh` adapted to your device's defconfig — and don't flash the
prebuilt image.

**Workaround without flashing**
Disable the freezer (costs memory management performance, but stops the
freezes):

```bash
adb shell device_config put activity_manager use_freezer false
adb shell settings put global cached_apps_freezer disabled
```

## Credits

- Upstream fix: `cgroup: prevent spurious transition into non-frozen state`
- LineageOS backport for 4.19: `LineageOS/android_kernel_qcom_sm8150`, `7a05073b`
- LineageOS issue #756 (same symptom on a52q / a72q / gta4l)
- AOSP `mkbootimg` / `unpack_bootimg` tools

## Disclaimer

Flashing a boot image can brick your device. You need an unlocked bootloader and
you should keep a backup of the stock boot partition. Everything here is
provided as-is, with no warranty. The patch is GPLv2 kernel code.
