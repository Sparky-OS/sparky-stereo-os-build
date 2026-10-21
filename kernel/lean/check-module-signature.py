#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Check an actual packaged module, without a pipe whose early exit hides errors."""
import lzma
from pathlib import Path
import sys
import tarfile

with tarfile.open(Path(sys.argv[1])) as archive:
    modules = [item for item in archive if item.isfile() and item.name.endswith('.ko.xz')]
    if not modules:
        raise SystemExit('Kernel image contains no compressed module')
    data = lzma.decompress(archive.extractfile(modules[0]).read())
    if not data.endswith(b'~Module signature appended~\n'):
        raise SystemExit('Packaged module has no appended signature')
    print('Packaged module signature marker verified:', modules[0].name)
