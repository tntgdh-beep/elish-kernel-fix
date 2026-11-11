#!/bin/bash
set -e
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export ARCH=arm64
export TMPDIR=/tmp
cd /root/kernel

echo "=== free antes ==="
free -m | head -2

echo "=== relink com GNU ld ==="
make -j4 O=out ARCH=arm64 \
  CC=clang LD=ld AR=llvm-ar NM=llvm-nm \
  OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip \
  Image

echo "=== verificacao ==="
strings out/arch/arm64/boot/Image | grep -m1 "^Linux version" || true
strings out/arch/arm64/boot/Image | grep -m1 "SMP preempt" || true
ls -l out/arch/arm64/boot/Image
echo BUILD_DONE
