#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright 2026 Daniel Campos Ramos
"""Apply the accepted stereo3d4 patch series to authenticated Debian revision 3."""
import argparse
from datetime import datetime, timezone
from email.utils import format_datetime
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tarfile

here = Path(__file__).resolve().parent
sys.path.insert(0, str(here.parents[1]))
from lean.debian_prepare import add_build_dependencies

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('source', type=Path)
parser.add_argument('edition_debian_archive', type=Path)
args = parser.parse_args()
source, archive = args.source.resolve(), args.edition_debian_archive.resolve()
version = subprocess.check_output(['dpkg-parsechangelog', '-l', str(source / 'debian/changelog'),
                                   '-S', 'Version'], text=True).strip()
assert version == '1:11.1.2+ds-3', 'Review a changed Debian source before rebasing'
assert not (source / 'debian/patches/stereo3d').exists()
with tarfile.open(archive) as retained:
    old_changelog = retained.extractfile('debian/changelog').read().decode()
    assert old_changelog.startswith('qemu (1:11.1.2+ds-1+stereo3d4) ')
    old_series = retained.extractfile('debian/patches/series').read().decode()
    stereo = [line for line in old_series.splitlines() if line.startswith('stereo3d/')]
    assert len(stereo) == 7 and len(set(stereo)) == 7
    patch_hashes = {}
    for name in stereo:
        assert Path(name).parent == Path('stereo3d') and name.endswith('.patch')
        member = retained.getmember('debian/patches/' + name)
        assert member.isfile()
        data = retained.extractfile(member).read()
        target = source / 'debian/patches' / name
        target.parent.mkdir(exist_ok=True)
        target.write_bytes(data)
        patch_hashes[name] = hashlib.sha256(data).hexdigest()
series = source / 'debian/patches/series'
series.write_text(series.read_text().rstrip() + '\n' + '\n'.join(stereo) + '\n')
subprocess.run(['dpkg-source', '--before-build', str(source)], check=True)
dependencies = (
    'libstereo-declare-dev (>= 1.3.0) [amd64]',
    'libspice-server-dev (>= 0.16.0+git20261010.acb8500-1+stereo3d2~) [amd64]',
)
for name in ['control', 'control-in']:
    path = source / 'debian' / name
    path.write_text(add_build_dependencies(path.read_text(), dependencies))
changelog = source / 'debian/changelog'
entry = '''qemu (1:11.1.2+ds-3+stereo3d5) unstable; urgency=medium

  * Retain Debian's virtio-gpu cleanup and migration security fixes, and
    its RISC-V vector fixes, with the accepted seven stereo3d4 patches.
  * Retain the stereo declaration and SPICE requirements in the generated
    control file and its source template.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  DATE

'''.replace('DATE', format_datetime(datetime.now(timezone.utc)))
changelog.write_text(entry + changelog.read_text())
(source / 'debian/stereo-rebase.json').write_text(json.dumps(dict(
    debian_version=version, edition_version='1:11.1.2+ds-3+stereo3d5',
    prior_edition_version='1:11.1.2+ds-1+stereo3d4',
    prior_debian_archive_sha256=hashlib.sha256(archive.read_bytes()).hexdigest(),
    unchanged_stereo_patches_sha256=patch_hashes), indent=2) + '\n')
print('Prepared QEMU Debian revision 3 plus the unchanged stereo patch series')
