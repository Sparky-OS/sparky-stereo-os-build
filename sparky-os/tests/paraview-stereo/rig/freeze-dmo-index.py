#!/usr/bin/env python3
"""freeze-dmo-index.py DIR -- under DIR/dists/forky (InRelease already there, signature checked by the caller), fetch every
index file the InRelease lists (a plain index made from its .xz) under main/ and non-free/ for binary-amd64, binary-all and i18n, check its SHA-256 and size
against the InRelease, and write it at its path and at its by-hash path (the Release says Acquire-By-Hash: yes)."""
import hashlib, lzma, sys, urllib.request
from pathlib import Path
root = Path(sys.argv[1]) / 'dists' / 'forky'
text = (root / 'InRelease').read_text()
body = text.split('-----BEGIN PGP SIGNATURE-----')[0]
sha = False; files = []
for line in body.splitlines():
    if line.startswith('SHA256:'):
        sha = True; continue
    if sha and not line.startswith(' '):
        sha = False
    if sha:
        h, size, name = line.split()
        if name.split('/')[0] in ('main', 'non-free') and name.split('/')[1] in ('binary-amd64', 'binary-all', 'i18n'):
            files.append((h, int(size), name))
names = {n for _, _, n in files}
for h, size, name in files:
    url = 'https://www.deb-multimedia.org/dists/forky/' + name
    try:
        if name + '.xz' in names:  # the server answers a plain index with the xz bytes: make it from the .xz
            data = lzma.decompress(urllib.request.urlopen(url + '.xz', timeout=120).read())
        else:
            data = urllib.request.urlopen(url, timeout=120).read()
    except Exception as e:
        print('skip', name, e); continue
    if len(data) != size or hashlib.sha256(data).hexdigest() != h:
        print('MISMATCH', name, len(data), size); sys.exit(1)
    for p in (root / name, root / Path(name).parent / 'by-hash' / 'SHA256' / h):
        p.parent.mkdir(parents=True, exist_ok=True); p.write_bytes(data)
    print('ok', name, size)
