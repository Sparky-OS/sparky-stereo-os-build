#!/usr/bin/env python3
"""Unpack Debian trixie's ovmf-ia32 (forky has none) into FWDIR/ovmf32-trixie, checksum checked, nothing installed."""
import hashlib, lzma, os, re, subprocess, sys, urllib.request
MIRROR = "https://deb.debian.org/debian/"
fwdir = sys.argv[1]
idx = lzma.decompress(urllib.request.urlopen(MIRROR + "dists/trixie/main/binary-all/Packages.xz", timeout=120).read()).decode()
m = re.search(r"^Package: ovmf-ia32\n(?:.*\n)*?Version: (\S+)\n(?:.*\n)*?Filename: (\S+)\n(?:.*\n)*?SHA256: (\S+)\n", idx, re.M)
ver, fn, sha = m.groups()
data = urllib.request.urlopen(MIRROR + fn, timeout=120).read()
assert hashlib.sha256(data).hexdigest() == sha, "checksum"
deb = os.path.join(fwdir, "dl", os.path.basename(fn))
open(deb, "wb").write(data)
subprocess.check_call(["dpkg-deb", "-x", deb, os.path.join(fwdir, "ovmf32-trixie")])
print("ovmf-ia32", ver, fn, sha)
