#!/system/bin/sh
echo "=== kernel ==="
uname -a
echo
echo "=== vermagic dos modulos carregados ==="
for m in /vendor/lib/modules/*.ko /vendor_dlkm/lib/modules/*.ko; do
  [ -f "$m" ] || continue
  v=$(strings "$m" 2>/dev/null | grep -m1 'SMP preempt')
  case "$v" in
    *4.19.325-cip136-st20-perf-g6b34d2476532*) ;;
    *) echo "DIVERGENTE: $(basename "$m") -> $v" ;;
  esac
done
echo "(sem linhas DIVERGENTE acima = todos os vermagic batem)"
echo
echo "=== modulos efetivamente carregados ==="
lsmod | wc -l
lsmod | head -12
echo
echo "=== erros de modulo no dmesg ==="
dmesg | grep -i -E 'version magic|disagrees about version|Unknown symbol|module verification failed|failed to load' | tail -15
echo "(vazio = ok)"
echo
echo "=== freezer ==="
if grep -q cgroup_freezer_frozen_exit /proc/kallsyms; then
  echo "ATENCAO: cgroup_freezer_frozen_exit ainda existe (patch nao aplicado?)"
else
  echo "ok: cgroup_freezer_frozen_exit ausente (patch aplicado)"
fi
echo
echo "=== wifi / rede ==="
ip -o link show 2>/dev/null | grep -E 'wlan|rmnet' | head -4
echo
echo "=== servicos quebrados ==="
dmesg | grep -i -E 'avc: denied.*(wlan|qca)|fatal' | tail -5
