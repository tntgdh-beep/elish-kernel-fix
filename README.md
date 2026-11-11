# Fix: travamento total do sistema ao usar o Chrome — Xiaomi Pad 5 Pro (elish), LineageOS 24.0

Backport do fix de cgroup freezer para o kernel `4.19.325-cip136` usado pelo
LineageOS 24.0 no `elish` (Xiaomi Pad 5 Pro, sm8250).

O patch muda **um único arquivo** (`kernel/cgroup/freezer.c`), não altera
símbolos exportados, então os módulos pré-compilados de `/vendor/lib/modules`
e `/vendor_dlkm` continuam carregando normalmente.

---

## Sintoma

Depois de algum tempo usando o Chrome (mais fácil com várias abas), o sistema
inteiro congela: a tela para de responder, o áudio trava, e alguns segundos
depois o aparelho reinicia sozinho no watchdog.

No `pstore`/`ramoops` aparece algo como:

```
sysrq: Kill All Tasks
```

ou o `system_server` é morto e o Android volta para a tela de bloqueio.

## Causa

O kernel 4.19 usa o freezer de cgroup v2 para congelar processos em cache.
A implementação em `cgroup_leave_frozen()` está desatualizada:

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

Quando sair do estado congelado corre com `vfork()` ou `do_signal_stop()`, o
contador `nr_frozen_tasks` do cgroup e o estado podem ir para "não congelado"
enquanto a tarefa continua logicamente congelada. Essa tarefa nunca mais
entra em `do_freezer_trap()`, fica presa, e o sistema trava até o watchdog
reiniciar o aparelho.

O LineageOS já corrigiu isso em outros kernels 4.19 (a52q, a72q, gta4l — veja
a issue #756), mas o `android_kernel_xiaomi_sm8250` (lineage-24.0) e o
`android_kernel_qcom_sm8250` (lineage-20) **não têm** o commit.

## O que o patch faz

Substitui o `recalc_sigpending()` por `JOBCTL_TRAP_FREEZE` + `TIF_SIGPENDING`,
que é a implementação atual do upstream:

```c
	} else if (!(current->jobctl & JOBCTL_TRAP_FREEZE)) {
		spin_lock(&current->sighand->siglock);
		current->jobctl |= JOBCTL_TRAP_FREEZE;
		set_thread_flag(TIF_SIGPENDING);
		spin_unlock(&current->sighand->siglock);
	}
```

Assim a tarefa é obrigada a passar por `do_freezer_trap()` antes de voltar
para o userspace, e a transição espúria para "não congelado" deixa de
acontecer.

Referência: `7a05073b` em `LineageOS/android_kernel_qcom_sm8150` (lineage-20),
`UPSTREAM: cgroup: prevent spurious transition into non-frozen state`.

---

## Compatibilidade

| Item | Valor |
|---|---|
| Aparelho | `elish` — Xiaomi Pad 5 Pro (M2105K81AC) |
| ROM | LineageOS 24.0 (`24.0-20261013-UNOFFICIAL-elish`) |
| Kernel | `4.19.325-cip136-st20-perf-g6b34d2476532` (commit `6b34d2476532`) |
| Slot | `boot_a` (o script serve para qualquer slot) |

Se a sua build do LineageOS for mais nova, o kernel dela pode ser outro
commit. Nesse caso **não flash** o `boot.img` pronto — recompile com o
`build-kernel.sh`, que baixa o commit certo.

Provavelmente vale para outros aparelhos com kernel 4.19 e o mesmo freezer de
cgroup v2 (sm8150/sm8250), mas só foi testado no `elish`.

---

## Opção A — flashar o `boot.img` já pronto (mais fácil)

Precisa de: bootloader destravado e `fastboot` no PC.

1. Baixe `boot_a_patched.img` na aba **Releases** deste repositório.
2. Faça backup do boot atual (recomendado):

   ```bash
   adb shell su -c "dd if=/dev/block/by-name/boot_a of=/sdcard/boot_stock.img"
   adb pull /sdcard/boot_stock.img
   ```

3. Flash:

   ```bash
   adb reboot bootloader
   fastboot flash boot_a boot_a_patched.img
   fastboot reboot
   ```

4. Confirme que subiu o kernel novo:

   ```bash
   adb shell uname -v
   # deve conter: #2 SMP PREEMPT Wed Nov 11 06:59:56 UTC 2026
   ```

### Rollback

```bash
fastboot flash boot_a boot_stock.img
```

## Opção B — compilar você mesmo

Precisa de Linux (x86_64 ou arm64) com:

```bash
sudo apt install build-essential bc bison flex libssl-dev libelf-dev \
  python3 cpio rsync device-tree-compiler clang lld llvm
```

```bash
./build-kernel.sh            # baixa o kernel, aplica o patch, compila
# saida: elish-kernel/src/out/arch/arm64/boot/Image
```

O script **aborta** se a versão do kernel não sair exatamente
`4.19.325-cip136-st20-perf-g6b34d2476532` — se mudar, os módulos de
`vendor_dlkm` não carregam e você fica sem Wi-Fi/GPU/touch.

Depois, monte o `boot.img`:

```bash
# no aparelho (precisa de root)
adb shell su -c "dd if=/dev/block/by-name/boot_a of=/sdcard/boot_stock.img"
adb pull /sdcard/boot_stock.img

python3 repack.py --stock boot_stock.img \
                  --image elish-kernel/src/out/arch/arm64/boot/Image \
                  --output boot_a_patched.img
```

O `repack.py` troca **só o kernel** e mantém o ramdisk e o
`os_version`/`os_patch_level` originais, e no final confere o resultado.

> Se o link final estourar memória, reduza o paralelismo:
> `JOBS=4 ./build-kernel.sh`

## Opção C — aplicar no build do LineageOS

```bash
cd kernel/xiaomi/sm8250        # android_kernel_xiaomi_sm8250
git am /caminho/0001-cgroup-freezer-prevent-spurious-transition.patch
```

Ou, para uso no `device/xiaomi/elish` via `repopick`/patch local, o arquivo
está em formato `git am` (com `From:`, `Subject:` e `Signed-off-by:`), então
funciona tanto com `git am` quanto com `patch -p1`.

---

## Como saber se o fix está ativo

O `uname -r` **não muda** (a versão é mantida de propósito). Use um destes:

```bash
# 1) build timestamp do kernel compilado com o patch
adb shell uname -v

# 2) o símbolo cgroup_freezer_frozen_exit ainda existe (é normal!) — ele só
#    sai com o commit seguinte, 28586903. O que muda é o código de
#    cgroup_leave_frozen, que deixa de chamar recalc_sigpending().
```

No kernel de referência, `cgroup_leave_frozen` tem 0xd4 bytes e não referencia
`recalc_sigpending`:

```
ffffff80101b07bc <cgroup_leave_frozen>:
...
ffffff80101b084c:  orr  x8, x8, #0x800000      <- JOBCTL_TRAP_FREEZE
```

---

## Avisos

- **Bootloader destravado é obrigatório.** O `boot.img` gerado não tem
  assinatura AVB, mas com `ro.boot.verifiedbootstate=orange` o bootloader
  aceita (mesmo mecanismo do Magisk).
- **Atualização do LineageOS sobrescreve o `boot`.** Depois de cada OTA você
  precisa flashar de novo (ou recompilar, se o kernel mudou).
- Este fix resolve o travamento causado pelo freezer de cgroup. Se o seu log
  mostra um crash nativo do `system_server` em BPF (tombstone), isso é outro
  problema e não é corrigido aqui.
- Alternativa sem flash, se você só quer parar de travar: desligar o freezer
  (perde desempenho de gerenciamento de memória):

  ```bash
  adb shell su -c "device_config put activity_manager use_freezer false"
  adb shell su -c "settings put global cached_apps_freezer disabled"
  ```

## Licença

O patch é um backport de código GPLv2 do kernel Linux; o restante (scripts,
documentação) pode ser usado livremente.
