#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Prepare the reviewed Debian Abseil source for the edition's matching pair."""
from datetime import datetime, timezone
from email.utils import format_datetime
from pathlib import Path
import shutil
import subprocess
import sys

here = Path(__file__).resolve().parent
source = Path(sys.argv[1]).resolve()
version = subprocess.check_output(['dpkg-parsechangelog', '-l', str(source / 'debian/changelog'),
                                   '-S', 'Version'], text=True).strip()
assert version == '20260526.0-2', 'Review changes in a newer Debian source first'
series = source / 'debian/patches/series'
patches = ['i386-vdso-entry-nop.patch', 'timeout-tests-representable-future.patch']
for name in patches:
    target = series.parent / name
    assert not target.exists(), 'Do not apply the edition patches twice'
    shutil.copy2(here / 'patches' / name, target)
series.write_text(series.read_text().rstrip() + '\n' + '\n'.join(patches) + '\n')
subprocess.run(['dpkg-source', '--before-build', str(source)], check=True)
changelog = source / 'debian/changelog'
entry = '''abseil (20260526.0-2+stereo3d1) unstable; urgency=medium

  * Build matching amd64/i386 packages to repair the archive's Multi-Arch skew.
  * Handle the Linux i386 fast-syscall entry NOP in stack unwinding.
  * Backport upstream c521584590af's representable-time test expectations.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  DATE

'''.replace('DATE', format_datetime(datetime.now(timezone.utc)))
changelog.write_text(entry + changelog.read_text())
print('Prepared Abseil 20260526.0-2+stereo3d1; apply Lean Code and build both architectures')
