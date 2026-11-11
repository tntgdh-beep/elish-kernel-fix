## Fix do travamento do Chrome no Xiaomi Pad 5 Pro (elish) — LineageOS 24.0

`boot_a_patched.img` com o backport de *cgroup: prevent spurious transition into
non-frozen state* (`7a05073b`), o mesmo fix que o LineageOS já aplicou em
a52q/a72q/gta4l (issue #756).

### Compatibilidade — leia antes

| Item | Valor |
|---|---|
| Aparelho | `elish` — Xiaomi Pad 5 Pro (M2105K81AC) |
| ROM | LineageOS 24.0 `24.0-20261013-UNOFFICIAL-elish` |
| Kernel | `4.19.325-cip136-st20-perf-g6b34d2476532` (commit `6b34d2476532`) |

Se a sua build é mais nova, **não use este arquivo** — recompile com o
`build-kernel.sh` do repositório. Kernel com versão diferente quebra o
carregamento dos módulos de `vendor_dlkm` (Wi-Fi, GPU, touch).

O ramdisk é **idêntico ao oficial**; só o kernel foi trocado.

### Como flashar

```bash
# backup do boot atual (recomendado)
adb shell su -c "dd if=/dev/block/by-name/boot_a of=/sdcard/boot_stock.img"
adb pull /sdcard/boot_stock.img

adb reboot bootloader
fastboot flash boot_a boot_a_patched.img
fastboot reboot
```

Verificação (o `uname -r` não muda de propósito):

```bash
adb shell uname -v
# #2 SMP PREEMPT Wed Nov 11 06:59:56 UTC 2026
```

### Rollback

```bash
fastboot flash boot_a boot_stock.img
```

Bootloader destravado é obrigatório (`ro.boot.verifiedbootstate=orange`).
A imagem não tem assinatura AVB, como esperado.

Detalhes completos, build e verificação: veja o `README.md` do repositório.
