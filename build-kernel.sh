#!/bin/bash
#
# Compila o kernel do Xiaomi Pad 5 Pro (elish / sm8250) com o backport do
# cgroup freezer, e deixa o "Image" pronto em $WORK/src/out/arch/arm64/boot/Image
#
# Uso:
#   ./build-kernel.sh [caminho-do-patch]
#
# Testado em host x86_64 (Ubuntu 22.04/24.04). Tambem funciona compilando
# nativamente em arm64 (foi assim que a imagem de referencia foi gerada).
#
set -euo pipefail

COMMIT=6b34d2476532
REPO="https://github.com/LineageOS/android_kernel_xiaomi_sm8250"
HERE="$(cd "$(dirname "$0")" && pwd)"
PATCH="${1:-$HERE/0001-cgroup-freezer-prevent-spurious-transition.patch}"
WORK="${WORK:-$PWD/elish-kernel}"

# ld.lld consome muita RAM no link final do vmlinux. Em host x86_64 e o
# caminho mais facil. Em maquina com pouca RAM, use LD=aarch64-linux-gnu-ld
# (precisa de binutils-aarch64-linux-gnu) ou reduza o -j.
JOBS="${JOBS:-$(nproc)}"
KERNEL_LD="${KERNEL_LD:-ld.lld}"

echo "== dependencias =="
for t in clang make bc flex bison python3 dtc; do
  command -v "$t" >/dev/null 2>&1 || { echo "FALTA: $t (veja o README)"; exit 1; }
done
clang --version | head -n 1

mkdir -p "$WORK"
cd "$WORK"

# IMPORTANTE: compilar a partir do tarball (sem .git). Se compilar de um
# clone git com alteracoes nao commitadas, o scripts/setlocalversion
# acrescenta "+" na versao e os modulos de vendor_dlkm param de carregar.
if [ ! -f src/Makefile ]; then
  echo "== baixando kernel @ $COMMIT =="
  curl -sSL -o kernel.tar.gz "$REPO/archive/$COMMIT.tar.gz"
  rm -rf src && mkdir -p src
  tar -xzf kernel.tar.gz -C src --strip-components=1
fi

cd src

if grep -q JOBCTL_TRAP_FREEZE kernel/cgroup/freezer.c; then
  echo "== patch ja aplicado =="
else
  echo "== aplicando patch =="
  patch -p1 --dry-run < "$PATCH"
  patch -p1 < "$PATCH"
fi

echo "== configurando =="
make -s O=out ARCH=arm64 vendor/kona-perf_defconfig
scripts/kconfig/merge_config.sh -m -O out out/.config \
  arch/arm64/configs/vendor/debugfs.config \
  arch/arm64/configs/vendor/xiaomi/sm8250-common.config \
  arch/arm64/configs/vendor/xiaomi/elish.config
# a versao precisa sair exatamente igual a do kernel oficial, senao os
# modulos pre-compilados de /vendor/lib/modules e /vendor_dlkm nao carregam
sed -i 's/^CONFIG_LOCALVERSION=.*/CONFIG_LOCALVERSION="-perf-g6b34d2476532"/' out/.config
sed -i 's/^CONFIG_LOCALVERSION_AUTO=y/# CONFIG_LOCALVERSION_AUTO is not set/' out/.config
make -s O=out olddefconfig
grep -E "^CONFIG_LOCALVERSION" out/.config

echo "== compilando (-j$JOBS) =="
make -j"$JOBS" O=out ARCH=arm64 \
  CC=clang CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-gnu- \
  LD="$KERNEL_LD" AR=llvm-ar NM=llvm-nm \
  OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip \
  Image

IMG=out/arch/arm64/boot/Image
echo "== verificacao =="
ls -l "$IMG"
VER=$(strings "$IMG" | grep -m1 "^Linux version" | awk '{print $3}')
echo "versao: $VER"
if [ "$VER" != "4.19.325-cip136-st20-perf-g6b34d2476532" ]; then
  echo "ERRO: versao inesperada. Os modulos de vendor_dlkm nao vao carregar."
  exit 1
fi
echo "OK: $PWD/$IMG"
