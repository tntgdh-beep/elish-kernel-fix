#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
cd /root/kernel/out || exit 1
V=vmlinux
[ -f "$V" ] || { echo "vmlinux nao encontrado"; exit 1; }
echo "=== simbolo ==="
llvm-nm "$V" | grep -w cgroup_leave_frozen
echo "=== tamanho do simbolo ==="
llvm-nm -S "$V" | grep -w cgroup_leave_frozen
echo "=== chama recalc_sigpending? ==="
llvm-objdump -d --no-show-raw-insn "$V" | awk '/<cgroup_leave_frozen>:/{f=1} f{print} f&&/^$/{exit}' > /tmp/leave_frozen.txt
wc -l < /tmp/leave_frozen.txt
grep -c 'recalc_sigpending' /tmp/leave_frozen.txt || echo "0 chamadas a recalc_sigpending"
echo "--- primeiras 40 linhas ---"
head -40 /tmp/leave_frozen.txt
