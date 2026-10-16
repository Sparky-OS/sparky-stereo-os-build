#!/usr/bin/env python3
"""fetch-fw.py : unpack the UEFI firmware the boot matrix needs, without installing anything.

  ovmf-generic from Debian forky   -> fw/ovmf-forky/usr/share/OVMF/   (x64 firmware, Secure Boot code, variable templates)
  ovmf-ia32  from Debian trixie  -> fw/ovmf32-trixie/usr/share/OVMF/ (32-bit firmware; forky has no ovmf-ia32)

The packages are read from the Debian mirror's Packages index and unpacked with `dpkg-deb -x`. Afterwards run
fw/mkvars.sh (needs virt-fw-vars from python3-virt-firmware) to make the variable stores in fw/vars/.
"""
import lzma, os, re, subprocess, sys, urllib.request

MIRROR = "https://deb.debian.org/debian/"
HERE = os.path.dirname(os.path.abspath(__file__))
WANT = [("forky", "ovmf-generic", "ovmf-forky"), ("trixie", "ovmf-ia32", "ovmf32-trixie")]
UA = {"User-Agent": "sparky-stereo-boot-matrix/1.0 (fetches two firmware packages)"}


def get(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120).read()


for suite, pkg, folder in WANT:
    index = lzma.decompress(get(f"{MIRROR}dists/{suite}/main/binary-all/Packages.xz")).decode()
    m = re.search(r"^Package: %s\n(?:.*\n)*?Filename: (\S+)\n(?:.*\n)*?SHA256: (\S+)\n" % re.escape(pkg), index, re.M)
    if not m:
        sys.exit(f"{pkg} not found in {suite}")
    filename, sha = m.groups()
    deb = os.path.join(HERE, os.path.basename(filename))
    data = get(MIRROR + filename)
    import hashlib
    if hashlib.sha256(data).hexdigest() != sha:
        sys.exit(f"checksum mismatch for {filename}")
    open(deb, "wb").write(data)
    out = os.path.join(HERE, folder)
    os.makedirs(out, exist_ok=True)
    subprocess.check_call(["dpkg-deb", "-x", deb, out])
    os.unlink(deb)
    print(f"{pkg} {filename.split('_')[1]} ({suite}) -> {out}")
