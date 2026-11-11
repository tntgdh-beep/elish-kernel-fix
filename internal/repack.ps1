# Repack do boot.img do elish com o kernel novo
# Uso: .\repack.ps1            -> so gera boot_a_patched.img
#      .\repack.ps1 -Flash     -> gera e flasha
param([switch]$Flash)

$ErrorActionPreference = "Stop"
$root   = "C:\Users\tnt\Desktop\elish-kernel-fix"
$tools  = "$root\tools"
$stock  = "C:\Users\tnt\Desktop\LineageOS-elish-bug-report\boot_a_stock.img"
$work   = "$root\work"
$newImg = "$work\Image"
$out    = "$root\boot_a_patched.img"
$serial = "e9d4d4b"

New-Item -ItemType Directory -Force -Path $work | Out-Null

Write-Host "== puxando Image do tablet =="
adb -s $serial pull /data/local/tmp/ubuntu/root/kernel/out/arch/arm64/boot/Image $newImg | Out-Null
Write-Host ("Image: {0:N1} MB" -f ((Get-Item $newImg).Length / 1MB))

Write-Host "== verificando versao =="
$pyCode = "import re; d=open(r'$newImg','rb').read(); m=re.search(rb'Linux version ([^\x00]{1,80})', d); print(m.group(1).decode('ascii','replace') if m else 'NAO_ENCONTRADO')"
$ver = python -c $pyCode
Write-Host ("versao encontrada: " + $ver)
if ($ver -notlike "4.19.325-cip136-st20-perf-g6b34d2476532*") {
  throw "Versao diferente da esperada! Modulos do vendor_dlkm nao vao carregar."
}

Write-Host "== desempacotando boot stock =="
if (Test-Path "$work\unpacked") { Remove-Item -Recurse -Force "$work\unpacked" }
python "$tools\unpack_bootimg.py" --boot_img $stock --out "$work\unpacked" | Out-Null

Write-Host "== gerando boot_a_patched.img =="
python "$tools\mkbootimg.py" --header_version 3 `
  --kernel "$newImg" `
  --ramdisk "$work\unpacked\ramdisk" `
  --os_version 17.0.0 --os_patch_level 2026-10 `
  --pagesize 4096 `
  --output $out

Write-Host ("boot_a_patched.img: {0:N1} MB" -f ((Get-Item $out).Length / 1MB))
Write-Host "OK. Imagem pronta em $out"

if ($Flash) {
  Write-Host "== reiniciando para o bootloader =="
  adb -s $serial reboot bootloader
  Start-Sleep -Seconds 25
  fastboot devices
  Write-Host "== flashando boot_a =="
  fastboot flash boot_a $out
  Write-Host "== reiniciando =="
  fastboot reboot
} else {
  Write-Host "Para flashar: .\repack.ps1 -Flash"
  Write-Host "Rollback:     fastboot flash boot_a `"$stock`""
}
