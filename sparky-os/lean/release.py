# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""Build and verify lc1 packages without changing upstream archives or published versions.

Run from sparky-os with `python3 -m lean.release`. build-tree replaces the final
dpkg-deb step of a build; check-debs is the mandatory gate before repository signing.
"""

import argparse
import hashlib
import json
import lzma
import os
from pathlib import Path
import subprocess
import tempfile

from . import archive, linkcheck, package


def projection_hash(path):
    h = hashlib.sha256()
    with lzma.open(path) as stream:
        for block in iter(lambda: stream.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()


def seal_iso(iso, manifest, proof):
    """A build attestation, generated only after the verified pre-squashfs pass."""
    iso, manifest, proof = map(Path, (iso, manifest, proof))
    if '-nolean-' in iso.name:
        raise package.Invalid('benchmark controls cannot be release images')
    obj = json.loads(proof.read_bytes())
    if obj.get('format') != 'lc1' or obj.get('scope') != 'iso-qualified-payload' or obj.get('renderer') != package.renderer():
        raise package.Invalid('ISO lacks a compatible pre-squashfs proof')
    if projection_hash(manifest) != obj.get('projection_sha256'):
        raise package.Invalid('ISO projection report differs from the pre-squashfs proof')
    stamp = {'format': 'lc1', 'scope': 'iso-release', 'iso_sha256': package.file_hash(iso),
             'manifest_sha256': package.file_hash(manifest), 'proof_sha256': package.file_hash(proof)}
    Path(str(iso) + '.lc1.json').write_bytes(package.encode(stamp))


def check_iso(iso):
    iso = Path(iso)
    stamp = json.loads(Path(str(iso) + '.lc1.json').read_bytes())
    manifest = Path(str(iso) + '.lean-code-projection.tsv.xz')
    proof = Path(str(iso) + '.lc-image.json')
    if '-nolean-' in iso.name or stamp.get('format') != 'lc1' or stamp.get('scope') != 'iso-release':
        raise package.Invalid('not an lc1 release image')
    for key, path in (('iso_sha256', iso), ('manifest_sha256', manifest), ('proof_sha256', proof)):
        if stamp.get(key) != package.file_hash(path):
            raise package.Invalid(f'{path}: differs from the lc1 build attestation')
    obj = json.loads(proof.read_bytes())
    if (obj.get('format') != 'lc1' or obj.get('scope') != 'iso-qualified-payload'
            or obj.get('renderer') != package.renderer()
            or obj.get('projection_sha256') != projection_hash(manifest)):
        raise package.Invalid('inconsistent pre-squashfs evidence')
    print(f'lc1: verified ISO build attestation: {iso.name}')


def build_tree(root, out):
    root, out = Path(root).resolve(), Path(out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='lc-build-') as work:
        hr = Path(work) / 'hr'
        obj = package.prepare(root, hr)
        trees = [root] + ([hr] if obj['hr_package'] else [])
        built = []
        for tree in trees:
            package.check_tree(tree)
            p, v, a = package.identity(package.control(tree))
            # Debian archive filenames omit the epoch; the control retains it.
            # dh_gencontrol registers this spelling in debian/files.
            dest = out / f'{p}_{v.split(":", 1)[-1]}_{a}.deb'
            if dest.exists():
                raise package.Invalid(f'{dest}: already exists; never replace a published version')
            temporary = Path(work) / dest.name
            subprocess.run(['dpkg-deb', '--root-owner-group', '-Zxz', '-b', str(tree), str(temporary)], check=True)
            built.append((temporary, dest))
        check_debs([str(src) for src, _ in built])
        # link refuses a racing same-name output; no replacement of existing artifacts.
        # Copy to the output filesystem first so /tmp and OUT may be on different devices.
        import shutil
        for src, dest in built:
            with tempfile.NamedTemporaryFile(dir=out, prefix='.lc-', delete=False) as stream:
                temp = Path(stream.name)
                try:
                    with src.open('rb') as source:
                        shutil.copyfileobj(source, stream)
                    stream.flush()
                    os.fchmod(stream.fileno(), 0o644)
                    os.link(temp, dest)
                finally:
                    temp.unlink(missing_ok=True)
            print(dest)


def check_debs(paths):
    """Check final archive bytes and require matching, independently marked HR companions."""
    verified, hr_blobs = {}, {}
    for deb in paths:
        with tempfile.TemporaryDirectory(prefix='lc-check-') as work:
            subprocess.run(['dpkg-deb', '--raw-extract', str(deb), work], check=True, stdout=subprocess.DEVNULL)
            obj = package.check_tree(work)
            key = (obj['package'], obj['version'], obj['architecture'])
            if key in verified:
                raise package.Invalid(f'duplicate package identity: {key}')
            verified[key] = obj
            if obj['package'].endswith('-lc-hr'):
                # Decompression is bounded by the projected file size cap.
                for row in obj['files']:
                    if row['kind'] == 'file' and row['path'].startswith(package.HR_BASE + '/'):
                        with package.lzma.open(Path(work) / row['path'][1:]) as stream:
                            data = stream.read(package.MAX_TEXT + 1)
                        if len(data) > package.MAX_TEXT:
                            raise package.Invalid('HR entry exceeds the source size limit')
                        hr_blobs[(key, row['path'])] = package.digest(data)
    for key, obj in verified.items():
        if not obj['hr_package']:
            continue
        hr_key = (obj['hr_package'], obj['version'], obj['architecture'])
        if hr_key not in verified:
            raise package.Invalid(f'{key}: matching HR documentation package is missing')
        for row in obj['files']:
            if row['status'] != 'projected':
                continue
            path = package.hr_path(obj['package'], obj['architecture'], row['sha_hr'])
            if hr_blobs.get((hr_key, path)) != row['sha_hr']:
                raise package.Invalid(f'{key}: HR missing or corrupt for {row["path"]}')
    print(f'lc1: verified {len(verified)} packages, payload hashes and required HR companions')
    return verified


def previous_build(deb, previous_dir=None, previous_debs=(), controls=None):
    """The newest build of the same package and architecture below `deb`'s version in previous_dir."""
    def field(path, name):
        if controls is not None and path in controls:
            return controls[path][name]
        return subprocess.run(['dpkg-deb', '-f', str(path), name], capture_output=True, text=True,
                              check=True).stdout.strip()

    def less(a, b):
        return subprocess.run(['dpkg', '--compare-versions', a, 'lt', b]).returncode == 0

    name, version, arch = (field(deb, key) for key in ('Package', 'Version', 'Architecture'))
    best = None
    candidates = list(map(Path, previous_debs))
    if previous_dir:
        if not Path(previous_dir).is_dir():
            raise package.Invalid(f'{previous_dir}: previous package directory is missing')
        candidates += list(Path(previous_dir).rglob(f'{name}_*_{arch}.deb'))
    for candidate in sorted(set(candidates)):
        if field(candidate, 'Package') != name or field(candidate, 'Architecture') != arch:
            continue
        found = field(candidate, 'Version')
        if less(found, version) and (best is None or less(best[0], found)):
            best = (found, candidate)
    return best[1] if best else None


def check_link(debs, previous_dir=None, smoke_table=None, archive_config=None, scratch=None, siblings=(),
               previous_siblings=(), min_free_gib=2, root_min_free_gib=12):
    """Qualify old/new edition snapshots against the same frozen public indexes."""
    archive_config = archive_config or os.environ.get('SPARKY_LC_ARCHIVE_CONFIG')
    scratch = scratch or os.environ.get('SPARKY_LC_SCRATCH')
    if not archive_config or not scratch:
        raise package.Invalid('check-link needs --archive-config / --scratch (or SPARKY_LC_ARCHIVE_CONFIG / '
                              'SPARKY_LC_SCRATCH); see lean/archive.md')
    debs = list(map(Path, debs))
    previous_inputs = list(map(Path, previous_siblings))
    if previous_dir:
        if not Path(previous_dir).is_dir():
            raise package.Invalid(f'{previous_dir}: previous package directory is missing')
        previous_inputs += sorted(Path(previous_dir).rglob('*.deb'))
    current_inputs = list(dict.fromkeys(debs + list(map(Path, siblings))))
    previous_inputs = list(dict.fromkeys(previous_inputs))
    controls = {path: archive.control(path) for path in dict.fromkeys(current_inputs + previous_inputs)}
    contexts = {}
    native = subprocess.run(['dpkg', '--print-architecture'], capture_output=True, text=True, check=True).stdout.strip()
    for deb in debs:
        arch = controls[deb]['Architecture']
        if arch == 'all':
            arch = native
        if arch != native:
            raise package.Invalid(f'{deb}: unsupported execution gate for {arch} on {native}; use a native runner')
        if arch not in contexts:
            contexts[arch] = archive.Archive(archive_config, scratch, arch, min_free_gib, root_min_free_gib)
        same_arch = [p for p in current_inputs if controls[p]['Architecture'] in (arch, 'all')]
        old_arch = [p for p in previous_inputs if controls[p]['Architecture'] in (arch, 'all')]
        for path in dict.fromkeys(same_arch + old_arch):
            frozen = contexts[arch].input(path)['control']
            if frozen != controls[path]:
                raise package.Invalid(f'{path}: control changed before the edition snapshot was frozen')
        previous = previous_build(deb, previous_debs=old_arch, controls=controls)
        linkcheck.check(deb, previous_deb=previous, smoke_table=smoke_table,
                        archive_context=contexts[arch], siblings=same_arch, previous_siblings=old_arch)
    print(f'lc1: archive-qualified link check passed for {len(debs)} packages')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    build = commands.add_parser('build-tree')
    build.add_argument('tree')
    build.add_argument('out')
    check = commands.add_parser('check-debs')
    check.add_argument('debs', nargs='+')
    link = commands.add_parser('check-link')
    link.add_argument('debs', nargs='+')
    link.add_argument('--previous-dir', help='directory holding the pre-lc1 builds to compare with')
    link.add_argument('--smoke', default=str(Path(__file__).with_name('smoke.tsv')), help='programs to start with LD_BIND_NOW=1')
    link.add_argument('--archive-config', help='JSON signed public archive sources (SPARKY_LC_ARCHIVE_CONFIG)')
    link.add_argument('--scratch', help='private APT state, verified cache and roots (SPARKY_LC_SCRATCH)')
    link.add_argument('--siblings-file', help='newline-separated authoritative current edition .debs')
    link.add_argument('--previous-siblings-file', help='previous edition snapshot .debs, including unchanged dependencies')
    link.add_argument('--min-free-gib', type=int, default=os.environ.get('SPARKY_LC_MIN_FREE_GIB', '2'), help='scratch floor, at least 2 GiB')
    link.add_argument('--root-min-free-gib', type=int, default=os.environ.get('SPARKY_LC_ROOT_MIN_FREE_GIB', '12'), help='root filesystem floor, at least 12 GiB')
    selection = commands.add_parser('check-selection')
    selection.add_argument('tsv')
    tree = commands.add_parser('check-tree')
    tree.add_argument('tree')
    repo = commands.add_parser('check-repo')
    repo.add_argument('root')
    seal = commands.add_parser('seal-iso')
    seal.add_argument('iso')
    seal.add_argument('manifest')
    seal.add_argument('proof')
    iso = commands.add_parser('check-iso')
    iso.add_argument('iso')
    args = parser.parse_args()
    try:
        if args.command == 'build-tree':
            build_tree(args.tree, args.out)
        elif args.command == 'check-debs':
            check_debs(args.debs)
        elif args.command == 'check-link':
            check_link(args.debs, args.previous_dir, args.smoke, args.archive_config, args.scratch,
                       Path(args.siblings_file).read_text().splitlines() if args.siblings_file else (),
                       Path(args.previous_siblings_file).read_text().splitlines() if args.previous_siblings_file else (),
                       args.min_free_gib, args.root_min_free_gib)
        elif args.command == 'check-selection':
            paths = [line.split('\t')[0] for line in Path(args.tsv).read_text().splitlines()
                     if line.split('\t')[-1] != 'source']
            if not paths:
                raise package.Invalid('empty package selection')
            check_debs(paths)
        elif args.command == 'check-repo':
            paths = sorted(Path(args.root).glob('pool/**/*.deb'))
            if not paths:
                raise package.Invalid('empty repository pool')
            check_debs(paths)
        elif args.command == 'seal-iso':
            seal_iso(args.iso, args.manifest, args.proof)
        elif args.command == 'check-iso':
            check_iso(args.iso)
        else:
            package.check_tree(args.tree)
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        parser.exit(1, f'lc1: release blocked: {exc}\n')


if __name__ == '__main__':
    main()
