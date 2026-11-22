# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""Build and verify lc1 packages without changing upstream archives or published versions.

Run from sparky-os with `python3 -m lean.release`. build-tree replaces the final
dpkg-deb step of a build; check-debs is the mandatory gate before repository signing.
"""

import argparse
import contextlib
import hashlib
import io
import json
import lzma
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

from . import VERSION, archive, buildrecord, identities, linkcheck, package, parallel, project


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


def toolkit_identity():
    """This toolkit certifies packages only with its VERSION's one released renderer (lean/identities.py)."""
    why = identities.toolkit_problem(VERSION, project.IDENTITY, project.CODE_SHA256)
    if why:
        raise package.Invalid(why)


def build_tree(root, out, preserve=None, retired=None):
    """preserve: a payload preservation plan ({installed pattern: reason}, package.preservation): those files stay as
    their authors ship them and the manifest says why."""
    toolkit_identity()
    root, out = Path(root).resolve(), Path(out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='lc-build-') as work:
        hr = Path(work) / 'hr'
        obj = package.prepare(root, hr, preserve=preserve, retired=retired)
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


def _checked(deb):
    """(manifest, architecture variant, copyright bytes, {HR path: authored digest}) of one final archive."""
    with tempfile.TemporaryDirectory(prefix='lc-check-') as work:
        subprocess.run(['dpkg-deb', '--raw-extract', str(deb), work], check=True, stdout=subprocess.DEVNULL)
        obj = package.check_tree(work)
        why = identities.problem(obj['renderer']['identity'], obj['renderer']['sha256'])
        if why:
            raise package.Invalid(f'{deb}: {why}')
        # An apt architecture variant (Architecture-Variant: amd64v3 in the control file, ORDER 108) shares its package, version and
        # architecture with its baseline twin; the variant is the rest of its identity, and its HR companion carries the same one.
        variant = package.control(Path(work)).get('architecture-variant', '')
        licence = Path(work) / 'usr/share/doc' / obj['package'] / 'copyright'
        blobs = {}
        if obj['package'].endswith('-lc-hr'):
            # Decompression is bounded by the projected file size cap.
            for row in obj['files']:
                if row['kind'] == 'file' and row['path'].startswith(package.HR_BASE + '/'):
                    with package.lzma.open(Path(work) / row['path'][1:]) as stream:
                        data = stream.read(package.MAX_TEXT + 1)
                    if len(data) > package.MAX_TEXT:
                        raise package.Invalid('HR entry exceeds the source size limit')
                    blobs[row['path']] = package.digest(data)
        return obj, variant, licence.read_bytes() if licence.is_file() and not licence.is_symlink() else None, blobs


def check_debs(paths):
    """Check final archive bytes and require matching, independently marked HR companions."""
    started = time.monotonic()
    verified, hr_blobs, copyrights, variants = {}, {}, {}, {}
    for obj, variant, licence, blobs in parallel.ordered(_checked, paths):
        key = (obj['package'], obj['version'], obj['architecture'] + (':' + variant if variant else ''))
        if key in verified:
            raise package.Invalid(f'duplicate package identity: {key}')
        verified[key] = obj
        variants[key] = variant
        copyrights[key] = licence
        hr_blobs.update(((key, path), sha) for path, sha in blobs.items())
    for key, obj in verified.items():
        if not obj['hr_package']:
            continue
        hr_key = (obj['hr_package'], obj['version'], obj['architecture'] + (':' + variants[key] if variants[key] else ''))
        if hr_key not in verified:
            raise package.Invalid(f'{key}: matching HR documentation package is missing')
        # ORDER 451c: the companion says exactly what its base package says about who wrote the packaging; build_tree copies the
        # base's final copyright (after provenance.sh) into it, and a pair from different builds is refused
        if copyrights[key] != copyrights[hr_key]:
            raise package.Invalid(f'{key}: the copyright file of {obj["hr_package"]} is not the copyright file of {obj["package"]}')
        for row in obj['files']:
            if row['status'] != 'projected':
                continue
            path = package.hr_path(obj['package'], obj['architecture'], row['sha_hr'])
            if hr_blobs.get((hr_key, path)) != row['sha_hr']:
                raise package.Invalid(f'{key}: HR missing or corrupt for {row["path"]}')
    print(f'lc1: verified {len(verified)} packages, payload hashes and required HR companions'
          f' in {time.monotonic() - started:.0f} s on {parallel.processors()} processors')
    return verified


def manifest_of(deb):
    """(package, version, architecture, manifest) of an lc1 archive, reading only its control and its manifest."""
    return package.deb_manifest(deb)


def check_identity(paths):
    """The Part 1 check of a publication round: every staged package's lc1 renderer pairs its label with the
    digest the version table gives it. Reads each archive's control and manifest only (check-debs, run by
    publish-tree's check-selection and by sync-to-server's check-repo, makes the same check with the full
    payload verification). Names every refused package, then refuses the set."""
    refused, seen = [], {}
    for deb in paths:
        try:
            p, v, a, obj = manifest_of(deb)
        except (OSError, ValueError, subprocess.CalledProcessError) as exc:
            refused.append(f'{deb}: {exc}')
            continue
        why = identities.problem(obj['renderer']['identity'], obj['renderer']['sha256'])
        if why:
            refused.append(f'{deb}: {why}')
            continue
        seen.setdefault(obj['renderer']['identity'], []).append(f'{p}_{v}_{a}')
    for line in refused:
        print(f'lc1: refused: {line}')
    for identity, names in sorted(seen.items()):
        print(f'lc1: {len(names)} packages: {identity}')
    if refused:
        raise package.Invalid(f'{len(refused)} of {len(paths)} packages carry a renderer the version table does not '
                              f'release (lean/identities.py)')
    print(f'lc1: verified {len(paths)} renderer identities against the version table')


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
               previous_siblings=(), min_free_gib=None, root_min_free_gib=1,
               previous_archive_config=None, previous_published_at=None, previous_archive_policy=None, archive_evidence=None, collect_predecessor_stops=False, allow_unavailable_baseline=False,
               reuse_manifest=None, reuse_seed=None, suite_record=None):
    """Qualify edition snapshots, optionally using a checked dated view for an unsolvable predecessor."""
    if reuse_manifest:
        options = locals().copy()
        from . import reuse
        return reuse.check(**options)
    archive_config = archive_config or os.environ.get('SPARKY_LC_ARCHIVE_CONFIG')
    scratch = scratch or os.environ.get('SPARKY_LC_SCRATCH')
    if not archive_config or not scratch:
        raise package.Invalid('check-link needs --archive-config / --scratch (or SPARKY_LC_ARCHIVE_CONFIG / '
                              'SPARKY_LC_SCRATCH); see lean/archive.md')
    if bool(previous_archive_config) != bool(previous_published_at):
        raise package.Invalid('dated predecessor needs both --previous-archive-config and --previous-published-at')
    debs = list(map(Path, debs))
    previous_inputs = list(map(Path, previous_siblings))
    if previous_dir:
        if not Path(previous_dir).is_dir():
            raise package.Invalid(f'{previous_dir}: previous package directory is missing')
        previous_inputs += sorted(Path(previous_dir).rglob('*.deb'))
    current_inputs = list(dict.fromkeys(debs + list(map(Path, siblings))))
    previous_inputs = list(dict.fromkeys(previous_inputs))
    every = list(dict.fromkeys(current_inputs + previous_inputs))
    controls = dict(zip(every, parallel.ordered(archive.control, every)))
    contexts = {}
    native = subprocess.run(['dpkg', '--print-architecture'], capture_output=True, text=True, check=True).stdout.strip()
    # each package as the loop of one process checked it, its notes printed and its refusal raised in this order;
    # a refusal before a package's check comes after the checks of the packages before it (ORDER 638)
    _LINK.update(contexts=contexts, smoke=smoke_table, plan=[], private={})
    stop = None
    dated_count = mixed_count = 0
    eligibility_stops, unusable, unavailable = [], [], []
    try:
        for deb in debs:
            arch = controls[deb]['Architecture']
            if arch == 'all':
                arch = native
            if arch != native:
                raise package.Invalid(f'{deb}: unsupported execution gate for {arch} on {native}; use a native runner')
            if arch not in contexts:
                contexts[arch] = archive.Archive(archive_config, scratch, arch, min_free_gib, root_min_free_gib)
                if archive_evidence:
                    from .historical import retain_view
                    retain_view(contexts[arch], archive_evidence)
                if previous_archive_config:
                    from .historical import PreviousView
                    selected = [p for p in debs if controls[p]['Architecture'] in (arch, 'all')]
                    contexts[arch].previous_view = PreviousView(contexts[arch], previous_archive_config,
                                                              previous_published_at, selected, previous_archive_policy, allow_unavailable_baseline)
            same_arch = [p for p in current_inputs if controls[p]['Architecture'] in (arch, 'all')]
            old_arch = [p for p in previous_inputs if controls[p]['Architecture'] in (arch, 'all')]
            contexts[arch].freeze(same_arch + old_arch)
            for path in dict.fromkeys(same_arch + old_arch):
                frozen = contexts[arch].input(path)['control']
                if frozen != controls[path]:
                    raise package.Invalid(f'{path}: control changed before the edition snapshot was frozen')
            previous = previous_build(deb, previous_debs=old_arch, controls=controls)
            _LINK['plan'].append((deb, arch, same_arch, old_arch, previous))
    except Exception as exc:
        stop = exc
    try:
        results = parallel.ordered(_linked, range(len(_LINK['plan'])))
        side_by_side = min(parallel.processors(), len(_LINK['plan'])) > 1
        for index in range(len(_LINK['plan'])):
            notes, error, predecessor = next(results)
            if isinstance(error, package.NoSpace) and side_by_side:
                side_by_side = False
                # side by side the packages share their disks: from this one on, one at a time, as a single process
                results.close()
                print(f'lc1: a disk floor was reached with packages checked side by side; {Path(_LINK["plan"][index][0]).name}'
                      ' and the packages after it are checked one at a time')
                results = map(_linked, range(index, len(_LINK['plan'])))
                notes, error, predecessor = next(results)
            sys.stdout.write(notes)
            if previous_archive_config:
                view = predecessor.get('view', 'none')
                print(f'lc1: {Path(_LINK["plan"][index][0]).name}: predecessor view={view}')
                for row in predecessor.get('archives', []):
                    print(f'lc1: {Path(_LINK["plan"][index][0]).name}: predecessor archive '
                          f'{row["archive"]}: {row["view"]}; {row["reason"]}; InRelease={row["InRelease_sha256"]}')
                if view in ('dated', 'mixed'):
                    dated_count += 1
                if view == 'mixed':
                    mixed_count += 1
            if predecessor.get('view') == 'no-baseline-available':
                unavailable.append({'input': str(_LINK['plan'][index][0]), **predecessor})
                print('lc1: no baseline available: ' + json.dumps(unavailable[-1], sort_keys=True))
            if predecessor.get('view') == 'uninstallable-at-publication':
                unusable.append({'input': str(_LINK['plan'][index][0]), **predecessor})
                for row in predecessor['missing_relations']:
                    print(f'lc1: published predecessor not installable at its publication: '
                          f'{Path(_LINK["plan"][index][0]).name}: missing {row["name"]}; '
                          f'successor providers={json.dumps(row["successor_dependencies"], sort_keys=True)}')
            if error is not None:
                from .historical import EligibilityStop
                if collect_predecessor_stops and isinstance(error, EligibilityStop):
                    entry = {'input': str(_LINK['plan'][index][0]), 'error': str(error), **predecessor}
                    eligibility_stops.append(entry)
                    print('lc1: predecessor eligibility STOP: ' + json.dumps(entry, sort_keys=True))
                else:
                    raise error
    finally:
        if collect_predecessor_stops:
            Path(scratch).mkdir(parents=True, exist_ok=True)
            (Path(scratch) / 'predecessor-stops.json').write_text(json.dumps(eligibility_stops, indent=2) + '\n')
            (Path(scratch) / 'uninstallable-predecessors.json').write_text(json.dumps(unusable, indent=2) + '\n')
            (Path(scratch) / 'unavailable-predecessors.json').write_text(json.dumps(unavailable, indent=2) + '\n')
        _LINK.clear()
    if stop is not None:
        raise stop
    if previous_archive_config:
        print(f'lc1: dated predecessor baselines: {dated_count} of {len(debs)}; mixed dated/current: {mixed_count}')
    print(f'lc1: no baseline available: {len(unavailable)} inputs')
    print(f'lc1: published predecessor not installable at its publication: {len(unusable)} inputs')
    for entry in unusable:
        print('lc1: repaired published input: ' + Path(entry['input']).name)
    if eligibility_stops:
        raise package.Invalid(f'{len(eligibility_stops)} uncovered predecessor eligibility stops after '
                              f'{len(debs)} inputs; see {Path(scratch) / "predecessor-stops.json"}')
    print(f'lc1: archive-qualified link check passed for {len(debs)} packages')


_LINK = {}


def _linked(index):
    """(printed notes, refusal or None) of one package's link check, in a context of this process's own."""
    deb, arch, same_arch, old_arch, previous = _LINK['plan'][index]
    if arch not in _LINK['private']:
        _LINK['private'][arch] = _LINK['contexts'][arch].private()
    out = io.StringIO()
    context = _LINK['private'][arch]
    context.predecessor_result = {}
    try:
        with contextlib.redirect_stdout(out):
            linkcheck.check(deb, previous_deb=previous, smoke_table=_LINK['smoke'],
                            archive_context=_LINK['private'][arch], siblings=same_arch, previous_siblings=old_arch)
    except Exception as exc:
        return out.getvalue(), exc, context.predecessor_result
    return out.getvalue(), None, context.predecessor_result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    build = commands.add_parser('build-tree')
    build.add_argument('tree')
    build.add_argument('out')
    build.add_argument('--preserve-plan', help='JSON {installed pattern: reason}: payload files kept exactly as their '
                                               'authors ship them (a vendor licence), each with its reason')
    check = commands.add_parser('check-debs')
    check.add_argument('debs', nargs='+')
    check.add_argument('--no-record', action='store_true',
                       help='only check; the default also writes the build record beside the .deb files (lean/buildrecord.py)')
    ident = commands.add_parser('check-identity', help='staged lc1 archives: renderer label and digest match the version table')
    ident.add_argument('debs', nargs='+')
    link = commands.add_parser('check-link')
    link.add_argument('debs', nargs='+')
    link.add_argument('--previous-dir', help='directory holding the pre-lc1 builds to compare with')
    link.add_argument('--smoke', default=str(Path(__file__).with_name('smoke.tsv')), help='programs to start with LD_BIND_NOW=1')
    link.add_argument('--archive-config', help='JSON signed public archive sources (SPARKY_LC_ARCHIVE_CONFIG)')
    link.add_argument('--collect-predecessor-stops', action='store_true', help='finish all inputs after recorded predecessor eligibility refusals; any uncovered refusal still exits 1')
    link.add_argument('--allow-unavailable-baseline', action='store_true', help='checked missing publication archive: candidate must pass without any baseline allowance')
    link.add_argument('--reuse-manifest', help='bound prior verdict records; requires seeded fresh certification on a code change')
    link.add_argument('--reuse-seed', help='deterministic fresh sample seed')
    link.add_argument('--suite-record', help='whole-toolkit exit/code/log binding for reuse certification')
    link.add_argument('--previous-archive-config', help='same signed archives in a dated predecessor view')
    link.add_argument('--previous-archive-policy', help='hashed per-archive search evidence for unchanged unrelated indexes')
    link.add_argument('--archive-evidence', help='retain authenticated archive views here for the round supply-chain record')
    link.add_argument('--previous-published-at', help='predecessor publication instant, ISO 8601 with timezone')
    link.add_argument('--scratch', help='private APT state, verified cache and roots (SPARKY_LC_SCRATCH)')
    link.add_argument('--siblings-file', help='newline-separated authoritative current edition .debs')
    link.add_argument('--previous-siblings-file', help='previous edition snapshot .debs, including unchanged dependencies')
    link.add_argument('--min-free-gib', type=int, default=os.environ.get('SPARKY_LC_MIN_FREE_GIB'),
                      help='scratch floor (default the house floor of its disk: 1 GiB on /, 2 GiB on another)')
    link.add_argument('--root-min-free-gib', type=int, default=os.environ.get('SPARKY_LC_ROOT_MIN_FREE_GIB', '1'),
                      help='root filesystem floor (the house floor, 1 GiB)')
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
            plan = json.loads(Path(args.preserve_plan).read_text()) if args.preserve_plan else None
            build_tree(args.tree, args.out, plan)
        elif args.command == 'check-debs':
            check_debs(args.debs)
            if not args.no_record:
                buildrecord.record(args.debs)
        elif args.command == 'check-identity':
            check_identity(args.debs)
        elif args.command == 'check-link':
            check_link(args.debs, args.previous_dir, args.smoke, args.archive_config, args.scratch,
                       Path(args.siblings_file).read_text().splitlines() if args.siblings_file else (),
                       Path(args.previous_siblings_file).read_text().splitlines() if args.previous_siblings_file else (),
                       args.min_free_gib, args.root_min_free_gib,
                       args.previous_archive_config, args.previous_published_at, args.previous_archive_policy, args.archive_evidence, args.collect_predecessor_stops, args.allow_unavailable_baseline,
                       args.reuse_manifest, args.reuse_seed, args.suite_record)
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
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:  # buildrecord.Incomplete is a ValueError
        parser.exit(1, f'lc1: release blocked: {exc}\n')


if __name__ == '__main__':
    main()
