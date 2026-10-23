#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Secure Boot signs the kernel image inside an unsigned linux-image .deb and keeps its Lean Code record true.

    SPARKY_SIGNING_KEY_DIR=/dir/with/key.pem+cert.pem sign-kernel-image.py IMAGE.deb OUTDIR

The build leaves the image unsigned (kernel/lean/stage.sh signs only when SPARKY_SIGNING_KEY_DIR is given while building).
The Lean Code manifest of the image package lists /boot/vmlinuz-RELEASE with its hash, md5sums list it too, and the control
file carries the manifest's hash, so replacing the file alone would fail `release check-debs`. This tool does exactly the
steps stage.sh does for a signed build, in the same order: sbsign the image, then the manifest row, the marker, md5sums and
Installed-Size of the package, then dpkg-deb, then check-debs on the result. The signed package keeps the name and version of
the unsigned one and goes to OUTDIR; publish only the signed one. Run it where sbsigntool and dpkg-deb are installed
(the validation image has them). The key is read by sbsign only; this tool never prints or copies it.
"""
from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'sparky-os'))
from lean import package, release


def main(deb, out):
    deb, out = Path(deb).resolve(), Path(out).resolve()
    keys = Path(os.environ['SPARKY_SIGNING_KEY_DIR'])
    out.mkdir(parents=True, exist_ok=True)
    target = out / deb.name
    if target.exists():
        raise SystemExit(f'{target}: exists; never replace a package')
    with tempfile.TemporaryDirectory(prefix='sign-kernel-') as work:
        tree = Path(work) / 'tree'
        subprocess.run(['dpkg-deb', '--raw-extract', str(deb), str(tree)], check=True)
        fields = package.control(tree)
        name, version, arch = package.identity(fields)
        package.check_tree(tree)
        images = sorted((tree / 'boot').glob('vmlinuz-*'))
        if len(images) != 1:
            raise SystemExit('expected exactly one /boot/vmlinuz-* in ' + deb.name)
        image = images[0]
        signed = Path(work) / 'vmlinuz.signed'
        subprocess.run(['sbsign', '--key', str(keys / 'key.pem'), '--cert', str(keys / 'cert.pem'),
                        '--output', str(signed), str(image)], check=True)
        subprocess.run(['sbverify', '--cert', str(keys / 'cert.pem'), str(signed)], check=True)
        mode = image.stat().st_mode & 0o7777
        signed.replace(image)
        image.chmod(mode)
        manifest = package.metadata_target(tree, package.manifest_path(name, arch))
        obj = json.loads(manifest.read_bytes())
        rows = [r for r in obj['files'] if r['path'] == '/' + image.relative_to(tree).as_posix()]
        if len(rows) != 1 or rows[0]['status'] != 'left':
            raise SystemExit('the image is not a single "left" row of the manifest')
        rows[0]['sha256'] = package.file_hash(image)
        rows[0]['bytes'] = image.stat().st_size
        raw = package.encode(obj)
        manifest.write_bytes(raw)
        package.set_fields(tree / 'DEBIAN/control', {package.FIELD: f'{package.FORMAT} {package.digest(raw)}'})
        sums, size = [], 0
        for real, row in package.entries(tree):
            if row['kind'] == 'file':
                sums.append(f'{package.file_hash(real, "md5")}  {row["path"][1:]}\n')
                size += (row['bytes'] + 1023) // 1024
        (tree / 'DEBIAN/md5sums').write_text(''.join(sorted(sums)))
        package.set_fields(tree / 'DEBIAN/control', {'Installed-Size': str(size)})
        package.check_tree(tree)
        temporary = Path(work) / deb.name
        subprocess.run(['dpkg-deb', '--root-owner-group', '-Zxz', '-b', str(tree), str(temporary)], check=True)
        release.check_debs([str(temporary)])
        temporary.replace(target) if temporary.stat().st_dev == out.stat().st_dev else (
            target.write_bytes(temporary.read_bytes()))
    print(target, package.file_hash(target))


if __name__ == '__main__':
    if len(sys.argv) != 3 or 'SPARKY_SIGNING_KEY_DIR' not in os.environ:
        raise SystemExit(__doc__)
    main(*sys.argv[1:])
