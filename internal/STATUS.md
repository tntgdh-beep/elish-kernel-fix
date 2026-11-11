# Build do kernel do elish — status

## ESTADO ATUAL: FLASHADO E BOOTANDO

- `boot_a_patched.img` gravado em `boot_a` (2026-11-11 ~09:48 UTC)
- Kernel rodando: `4.19.325-cip136-st20-perf-g6b34d2476532 #2 SMP PREEMPT
  Wed Nov 11 06:59:56 UTC 2026`
- Wi-Fi (`wlan0`) up, nenhum erro de vermagic/`Unknown symbol` no dmesg
- Patch confirmado no binário: `cgroup_leave_frozen` nao chama mais
  `recalc_sigpending` e seta `JOBCTL_TRAP_FREEZE` (bit 0x800000)
- Mitigações temporárias revertidas (freezer voltou ao padrão do sistema):
  `use_freezer`, `use_compaction`, `zram_writeback_enabled`,
  `cached_apps_freezer` -> `null`

### Rollback (se precisar)

```
fastboot flash boot_a "C:\Users\tnt\Desktop\LineageOS-elish-bug-report\boot_a_stock.img"
```

## Resumo

Compilando o kernel corrigido **no proprio tablet** (Ubuntu 24.04 em chroot,
nativo arm64), porque as duas outras rotas travaram:

| Rota | Situacao |
|---|---|
| WSL2 no PC | Bloqueado: o Windows tem servicing pendente (`CBS RebootPending`), o `vmcompute` nao existe e o WSL nao cria a VM (`HCS_E_SERVICE_NOT_AVAILABLE`). Precisa de reboot. |
| GitHub Actions | Bloqueado: o token do `gh` nao tem o escopo `workflow`, entao nao da para subir `.github/workflows/build.yml`. Precisa de um clique em github.com/login/device. |
| **Tablet (chroot)** | **Usada** — `/data/local/tmp/ubuntu`, build em `/root/kernel`, `Image` gerado com sucesso. |

## Ambiente no tablet

- Ubuntu 24.04 arm64 (ubuntu-base) em `/data/local/tmp/ubuntu`
- clang 18.1.3 + lld, make, bc, flex, bison, libssl-dev, libelf-dev, dtc
- Fonte: `LineageOS/android_kernel_xiaomi_sm8250` @ `6b34d2476532`
- Patch do cgroup freezer aplicado
- Config: `vendor/kona-perf_defconfig` + `debugfs.config` + `xiaomi/sm8250-common.config` + `xiaomi/elish.config`
- `CONFIG_LOCALVERSION="-perf-g6b34d2476532"`, `LOCALVERSION_AUTO` desligado
- Build: `make -j4 Image` (log em `/root/build.log` dentro do chroot)

## Comandos uteis

```powershell
# ver o log
adb -s e9d4d4b shell "tail -5 /data/local/tmp/ubuntu/root/build.log"

# reiniciar o build (idempotente: nao reextrai nem reaplica patch)
adb -s e9d4d4b push .\build-tablet.sh /data/local/tmp/ubuntu/root/build-tablet.sh
adb -s e9d4d4b shell "chroot /data/local/tmp/ubuntu /bin/bash -c 'export PATH=/usr/bin:/bin:/usr/sbin:/sbin; nohup bash /root/build-tablet.sh > /root/build.log 2>&1 &'"

# montar o boot.img (nao flasha)
.\repack.ps1

# montar e flashar
.\repack.ps1 -Flash

# rollback
fastboot flash boot_a "C:\Users\tnt\Desktop\LineageOS-elish-bug-report\boot_a_stock.img"
```

## Verificacao obrigatoria antes de flashar

A string de versao dentro do `Image` tem que ser exatamente:

```
4.19.325-cip136-st20-perf-g6b34d2476532
```

Senao os modulos de `vendor_dlkm` (Wi-Fi, GPU, touch) nao carregam. O
`repack.ps1` aborta se nao bater.

## Sobre AVB

O `boot_a_stock.img` tem rodape AVB (`AVBf`), mas o tablet esta com
`ro.boot.verifiedbootstate=orange` (bootloader destravado), entao boot
modificado e aceito — mesmo mecanismo do Magisk. O `boot_a_patched.img`
gerado nao tem assinatura AVB, e isso e esperado.
