# Texto pronto para divulgar

## Português (Telegram / XDA / fórum)

> **Fix para o travamento do Chrome no Pad 5 Pro (elish) — LineageOS 24.0**
>
> Quem usa o `elish` com o LineageOS 24.0 e trava o sistema inteiro ao abrir o
> Chrome (tela congela e o aparelho reinicia no watchdog, com
> `sysrq: Kill All Tasks` no log) — a causa é o kernel 4.19 do
> `android_kernel_xiaomi_sm8250` estar sem o fix de cgroup freezer que o
> LineageOS já aplicou no a52q/a72q/gta4l (issue #756).
>
> Fiz o backport, compilei e estou usando. O patch muda só
> `kernel/cgroup/freezer.c`, então os módulos de `vendor_dlkm` continuam
> carregando normalmente.
>
> - Patch + instruções de build: https://github.com/tntgdh-beep/elish-kernel-fix
> - `boot.img` pronto (para a build `24.0-20261013-UNOFFICIAL-elish`):
>   https://github.com/tntgdh-beep/elish-kernel-fix/releases/tag/elish-24.0-20261013
>
> Para flashar (bootloader destravado):
>
> ```
> adb shell su -c "dd if=/dev/block/by-name/boot_a of=/sdcard/boot_stock.img"
> adb pull /sdcard/boot_stock.img
> adb reboot bootloader
> fastboot flash boot_a boot_a_patched.img
> fastboot reboot
> ```
>
> Rollback: `fastboot flash boot_a boot_stock.img`
>
> **Atenção:** se a sua build do LineageOS for mais nova que a de 13/10/2026,
> não flash o `boot.img` pronto — recompile com o `build-kernel.sh` do repo,
> senão os módulos de Wi-Fi/GPU/touch não carregam.
>
> Enquanto não flashar, dá para parar os travamentos desligando o freezer:
> `device_config put activity_manager use_freezer false` +
> `settings put global cached_apps_freezer disabled` (perde desempenho de
> gerenciamento de memória).

## English (issue tracker / XDA)

> **Fix for the Chrome full-system freeze on elish (Xiaomi Pad 5 Pro), LineageOS 24.0**
>
> The freeze + watchdog reboot (`sysrq: Kill All Tasks` in the log) is the same
> cgroup freezer bug that LineageOS fixed for a52q/a72q/gta4l (issue #756).
> `android_kernel_xiaomi_sm8250` (lineage-24.0) is still missing that commit.
>
> Backport of `7a05073b` ("cgroup: prevent spurious transition into non-frozen
> state"), touching only `kernel/cgroup/freezer.c`, so the prebuilt
> `vendor_dlkm` modules keep loading (kernel version string is unchanged).
>
> - Patch + build instructions: https://github.com/tntgdh-beep/elish-kernel-fix
> - Prebuilt boot image (build `24.0-20261013-UNOFFICIAL-elish`):
>   https://github.com/tntgdh-beep/elish-kernel-fix/releases/tag/elish-24.0-20261013
>
> Flash (unlocked bootloader):
>
> ```
> adb shell su -c "dd if=/dev/block/by-name/boot_a of=/sdcard/boot_stock.img"
> adb pull /sdcard/boot_stock.img
> adb reboot bootloader
> fastboot flash boot_a boot_a_patched.img
> fastboot reboot
> ```
>
> Rollback: `fastboot flash boot_a boot_stock.img`
>
> **Note:** if your LineageOS build is newer than 2026-10-13, do not flash the
> prebuilt image — rebuild with `build-kernel.sh` instead, otherwise the
> vendor_dlkm modules will fail to load.
