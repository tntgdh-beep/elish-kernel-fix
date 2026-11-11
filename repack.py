#!/usr/bin/env python3
"""
Repack an Android boot image (header v3) replacing only the kernel.

Keeps the original ramdisk, os_version and os_patch_level, so the
result differs from the stock image only in the kernel payload.

Usage:
    python repack.py --stock boot_stock.img --image Image --output boot_patched.img

Requires: python3 (stdlib only). The AOSP mkbootimg scripts are expected
in ./tools next to this file.
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.join(HERE, "tools")


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("comando falhou: %s\n%s%s" % (" ".join(cmd), r.stdout, r.stderr))
    return r.stdout


def unpack(path, outdir):
    txt = run([sys.executable, os.path.join(TOOLS, "unpack_bootimg.py"),
               "--boot_img", path, "--out", outdir])
    info = {}
    for line in txt.splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            info[k.strip()] = v.strip()
    return info


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stock", required=True, help="boot.img original (extraido do aparelho)")
    ap.add_argument("--image", required=True, help="Image novo compilado")
    ap.add_argument("--output", required=True, help="boot.img de saida")
    ap.add_argument("--pagesize", default="4096")
    args = ap.parse_args()

    work = tempfile.mkdtemp(prefix="bootimg_")
    try:
        info = unpack(args.stock, work)
        hv = info.get("boot image header version", "?")
        osver = info.get("os version", "")
        ospatch = info.get("os patch level", "")
        print("stock : header v%s, os_version %s, patch %s" % (hv, osver, ospatch))
        if hv != "3":
            print("AVISO: header v%s; este script foi testado apenas com v3" % hv)

        ksize = int(info.get("kernel_size", "0"))
        rsize = int(info.get("ramdisk size", "0"))
        newsize = os.path.getsize(args.image)
        print("kernel: stock %d bytes -> novo %d bytes" % (ksize, newsize))

        cmd = [sys.executable, os.path.join(TOOLS, "mkbootimg.py"),
               "--header_version", hv,
               "--kernel", args.image,
               "--ramdisk", os.path.join(work, "ramdisk"),
               "--pagesize", args.pagesize,
               "--output", args.output]
        if osver:
            cmd += ["--os_version", osver]
        if ospatch:
            cmd += ["--os_patch_level", ospatch]
        run(cmd)
        print("gerado: %s (%d bytes)" % (args.output, os.path.getsize(args.output)))

        # sanidade: reabre a imagem gerada e confere kernel/ramdisk
        chk = tempfile.mkdtemp(prefix="bootchk_")
        try:
            cinfo = unpack(args.output, chk)
            ok_k = int(cinfo.get("kernel_size", "0")) == newsize
            ok_r = int(cinfo.get("ramdisk size", "0")) == rsize
            print("verificacao: kernel ok=%s, ramdisk ok=%s" % (ok_k, ok_r))
            if not (ok_k and ok_r):
                sys.exit("imagem gerada nao confere!")
        finally:
            shutil.rmtree(chk, ignore_errors=True)
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
