#!/bin/bash
set -e
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export ARCH=arm64
export TMPDIR=/tmp
mkdir -p /tmp && chmod 1777 /tmp
cd /root

if [ ! -f kernel/Makefile ]; then
  echo "=== extraindo fonte ==="
  rm -rf kernel
  mkdir -p kernel
  tar -xzf kernel.tar.gz -C kernel --strip-components=1
fi

cd kernel

if ! grep -q JOBCTL_TRAP_FREEZE kernel/cgroup/freezer.c; then
  echo "=== aplicando patch ==="
  patch -p1 < /root/fix.patch
else
  echo "=== patch ja aplicado ==="
fi

if [ ! -f out/.config ]; then
  echo "=== configurando ==="
  make -s O=out vendor/kona-perf_defconfig
  scripts/kconfig/merge_config.sh -m -O out out/.config \
    arch/arm64/configs/vendor/debugfs.config \
    arch/arm64/configs/vendor/xiaomi/sm8250-common.config \
    arch/arm64/configs/vendor/xiaomi/elish.config
  sed -i 's/^CONFIG_LOCALVERSION=.*/CONFIG_LOCALVERSION="-perf-g6b34d2476532"/' out/.config
  sed -i 's/^CONFIG_LOCALVERSION_AUTO=y/# CONFIG_LOCALVERSION_AUTO is not set/' out/.config
  make -s O=out olddefconfig
  grep -E "^CONFIG_LOCALVERSION" out/.config
fi

echo "=== compilando ==="
make -j4 O=out ARCH=arm64 \
  CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm \
  OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip \
  Image

echo "=== verificacao ==="
strings out/arch/arm64/boot/Image | grep -m1 "^Linux version" || true
strings out/arch/arm64/boot/Image | grep -m1 "SMP preempt" || true
ls -l out/arch/arm64/boot/Image
echo BUILD_DONE
