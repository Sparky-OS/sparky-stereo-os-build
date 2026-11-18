#!/usr/bin/python3
# Copyright 2026 Daniel Ramos (Capitain Jack), GPL-3.0-or-later.
"""A pinned build compiler, never a processing model or an installed payload."""
import hashlib
from pathlib import Path
import ssl
import sys
import tarfile
import urllib.request

root = Path(sys.argv[1]).resolve()
version = '2026.12.0.1'
url = f'https://github.com/shader-slang/slang/releases/download/v{version}/slang-{version}-linux-x86_64.tar.gz'
expected = 'bbd36968b5aefdf91c2ede0d2e131f8b552cba6ed2444da59f1a0bc0bfc6792d'
archive = root / '.slang-toolchain.tar.gz'
root.mkdir(exist_ok=True)
if not archive.is_file() or hashlib.sha256(archive.read_bytes()).hexdigest() != expected:
    temporary = archive.with_suffix('.download')
    request = urllib.request.Request(url, headers={'User-Agent':'Spirula-Studio-build'})
    with urllib.request.urlopen(request,context=ssl.create_default_context()) as source, temporary.open('wb') as target:
        while block := source.read(1024*1024):
            target.write(block)
            if target.tell() > 76807913:
                raise ValueError('Slang archive size')
    if temporary.stat().st_size != 76807913 or hashlib.sha256(temporary.read_bytes()).hexdigest() != expected:
        temporary.unlink()
        raise ValueError('Slang archive SHA256/size')
    temporary.replace(archive)
if not (root/'bin/slangc').is_file():
    with tarfile.open(archive) as tar:
        tar.extractall(root,filter='data')
print(f'Slang {version} | {expected} | {url}')
