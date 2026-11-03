#!/usr/bin/python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/03
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/03
"""NVIDIA's 580 user space carried as edition packages (ORDER 354): NVIDIA's files byte for byte, the control ours.

  carry.py select INDEX NV_VERSION EXCLUDED OUT_TSV   the packages of NVIDIA's index at NV_VERSION that the edition carries
                                                      (every one not listed in EXCLUDED, which must name only packages there)
  carry.py check-index INDEX NV_VERSION PACKAGES EXCLUDED
                                                      PACKAGES and EXCLUDED cover NVIDIA's index at NV_VERSION exactly, and
                                                      the index lists each carried file with the recorded SHA-256 and size
  carry.py stage DEB NV_VERSION VERSION PACKAGES CHANGELOG README COPYRIGHT WORK
                                                      WORK/tree: the staging tree of the edition's package; WORK/plan.json: the
                                                      Lean Code preservation plan (every NVIDIA payload file); WORK/nvidia.json:
                                                      NVIDIA's payload and maintainer files, for verify. COPYRIGHT is NVIDIA's
                                                      copyright file (the NVIDIA Software License), which a package NVIDIA ships
                                                      without one (its i386 packages, cuda-drivers) gets byte for byte
  carry.py verify BUILT NVIDIA_JSON                   the built package against NVIDIA's: every NVIDIA file and maintainer file
                                                      identical, only the edition's three files added, and the control changed
                                                      only where the edition changes it; prints the SHA-256 list

The NVIDIA Software License distributes the binary files only unmodified and asks that a modified file carry a notice
of the change, so no file NVIDIA authored is changed: the version and the relations live in the control file, the edition's
changelog entry in changelog.Debian.ARCH.gz (Debian's binary-only changelog name), and the record of what is NVIDIA's in
README.sparky-stereo and the Lean Code manifest.
"""
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile

MAINTAINER = 'Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>'
HOMEPAGE = 'https://sparkylinux.org'
BUGS = 'https://github.com/Sparky-OS/sparky-stereo-os/issues'
RELATIONS = ('Pre-Depends', 'Depends', 'Recommends', 'Suggests', 'Enhances', 'Breaks', 'Conflicts', 'Replaces', 'Provides')
# The kernel module NVIDIA's packages depend on at their exact version: the edition's module provides it at the carried one.
MODULE_NAMES = {'nvidia-kernel-dkms'}
# Lean Code's own bound on the client, which it adds to every package it marks (package.prepare)
LEAN_BREAKS = 'dpkg-stereo (<< 0.1.6)'
CHANGED = {'version', 'source', 'maintainer', 'original-maintainer', 'homepage', 'bugs', 'description', 'installed-size',
           'sparky-lean-code', 'breaks', *(r.lower() for r in RELATIONS)}
PRESERVED_ADDED = ("NVIDIA's copyright file, the one NVIDIA's amd64 packages ship, byte for byte, added where NVIDIA ships "
                   "none: the Agreement goes to each recipient (NVIDIA Software License 1.1(d)(ii); Debian Policy 2.3)")
PRESERVED = ("NVIDIA's file, kept as NVIDIA ships it: the NVIDIA Software License distributes the binary files only "
             "unmodified (1.1(d)(i), 2.3) and asks that a modified file carry a prominent notice of the change (2.5)")


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def index(path, version):
    """{(package, architecture): fields} of an APT Packages index at one version."""
    opener = gzip.open if str(path).endswith('.gz') else open
    with opener(path, 'rt', encoding='utf-8') as stream:
        text = stream.read()
    out = {}
    for record in text.split('\n\n'):
        fields, key = {}, None
        for line in record.splitlines():
            if line[:1].isspace() and key:
                fields[key] += '\n' + line
            elif ':' in line:
                key, _, value = line.partition(':')
                fields[key] = value.strip()
        if fields.get('Version') == version:
            out[(fields['Package'], fields['Architecture'])] = fields
    return out


def rows(path):
    for line in Path(path).read_text().splitlines():
        if line and not line.startswith('#'):
            yield line.split('\t')


def select(index_path, version, excluded_path, out_path):
    recs = index(index_path, version)
    excluded = {(r[0], r[1]) for r in rows(excluded_path)}
    absent = sorted(excluded - set(recs))
    if absent:
        sys.exit(f'excluded but not in the index at {version}: {absent}')
    lines = ['# NVIDIA\'s packages the edition carries: package, architecture, file in NVIDIA\'s repository, size, SHA-256 '
             '(from NVIDIA\'s signed index for Debian 12; carry.py select writes this file, check-index checks it)']
    for key in sorted(set(recs) - excluded, key=lambda k: (k[1], k[0])):
        f = recs[key]
        lines.append('\t'.join([key[0], key[1], f['Filename'].removeprefix('./'), f['Size'], f['SHA256']]))
    Path(out_path).write_text('\n'.join(lines) + '\n')
    print(f'{len(lines) - 1} carried, {len(excluded)} excluded, of {len(recs)} at {version}')


def check_index(index_path, version, packages_path, excluded_path):
    recs = index(index_path, version)
    carried = {(r[0], r[1]): r for r in rows(packages_path)}
    excluded = {(r[0], r[1]): r for r in rows(excluded_path)}
    problems = []
    if set(carried) & set(excluded):
        problems.append(f'carried and excluded: {sorted(set(carried) & set(excluded))}')
    if set(recs) != set(carried) | set(excluded):
        problems.append(f'index and lists differ: index only {sorted(set(recs) - set(carried) - set(excluded))}, '
                        f'lists only {sorted(set(carried) | set(excluded) - set(recs))}')
    for key, (_, _, filename, size, digest) in carried.items():
        f = recs.get(key)
        if f and (f['Filename'].removeprefix('./'), f['Size'], f['SHA256']) != (filename, size, digest):
            problems.append(f'{key}: the index lists {f["Filename"]} {f["Size"]} {f["SHA256"]}')
    for key, row in excluded.items():
        if len(row) != 3 or not row[2].strip():
            problems.append(f'{key}: an exclusion needs its reason')
    if problems:
        sys.exit('\n'.join(problems))
    print(f'NVIDIA\'s index at {version}: {len(carried)} carried with the recorded hashes, {len(excluded)} excluded with reasons')


def control_paragraph(text):
    """Ordered (field, value) pairs of one deb822 paragraph, continuation lines kept in the value."""
    pairs = []
    for line in text.rstrip('\n').split('\n'):
        if line[:1].isspace() and pairs:
            pairs[-1][1] += '\n' + line
        else:
            key, _, value = line.partition(':')
            pairs.append([key, value.strip()])
    return pairs


def rewrite_relation(value, names, nv_version, version):
    """NVIDIA's exact relations to the carried packages (name (= NV_VERSION)) at the carried version; every other relation
    stays as NVIDIA wrote it."""
    def one(match):
        name = match.group(1)
        if name.split(':')[0] in names and match.group(3) == nv_version:
            return f'{name} ({match.group(2)} {version})'
        return match.group(0)
    return re.sub(r'([a-z0-9][a-z0-9+.-]*(?::[a-z0-9]+)?)\s*\(\s*(=)\s*([^)\s]+)\s*\)', one, value)


def payload(tar_bytes):
    """{path: (kind, mode, sha256 or link target, owner)} of a .deb's data archive."""
    out = {}
    with tarfile.open(fileobj=io.BytesIO(tar_bytes)) as tar:
        for member in tar.getmembers():
            path = '/' + member.name.removeprefix('./').rstrip('/')
            if path == '/':
                continue
            owner = f'{member.uname or member.uid}:{member.gname or member.gid}'
            if member.isdir():
                out[path] = ('dir', member.mode, '', owner)
            elif member.issym():
                out[path] = ('symlink', member.mode, member.linkname, owner)
            elif member.islnk():
                raise SystemExit(f'{path}: a hard link (NVIDIA ships none at 580.196.07; this tool does not carry them)')
            elif member.isfile():
                out[path] = ('file', member.mode, sha256(tar.extractfile(member).read()), owner)
            else:
                raise SystemExit(f'{path}: special file in the data archive')
    return out


def deb_parts(deb):
    data = subprocess.run(['dpkg-deb', '--fsys-tarfile', deb], check=True, capture_output=True).stdout
    control = subprocess.run(['dpkg-deb', '--ctrl-tarfile', deb], check=True, capture_output=True).stdout
    scripts = {}
    with tarfile.open(fileobj=io.BytesIO(control)) as tar:
        for member in tar.getmembers():
            name = member.name.removeprefix('./')
            if member.isfile():
                scripts[name] = (member.mode, tar.extractfile(member).read())
    return payload(data), scripts


def plan_pattern(path):
    return re.sub(r'([][*?])', r'[\1]', path)


def stage(deb, nv_version, version, packages_path, changelog, readme, copyright_path, work):
    work = Path(work)
    tree = work / 'tree'
    if work.exists():
        sys.exit(f'{work}: must be new')
    work.mkdir(parents=True)
    names = {r[0] for r in rows(packages_path)} | MODULE_NAMES
    files, scripts = deb_parts(deb)
    subprocess.run(['dpkg-deb', '-R', deb, str(tree)], check=True)
    owners = sorted({v[3] for v in files.values()} - {'root:root'})
    if owners:
        sys.exit(f'{deb}: files not owned by root ({owners}); dpkg-deb --root-owner-group would change them')
    pairs = control_paragraph((tree / 'DEBIAN/control').read_text())
    fields = {k.lower(): v for k, v in pairs}
    package, arch = fields['package'], fields['architecture']
    if fields['version'] != nv_version:
        sys.exit(f'{deb}: version {fields["version"]}, not {nv_version}')
    doc = f'/usr/share/doc/{package}'
    ours = {f'{doc}/README.sparky-stereo', f'{doc}/changelog.Debian.{arch}.gz'}
    taken = sorted(p for p in ours if p in files)
    if taken:
        sys.exit(f'{deb}: NVIDIA ships {taken}')
    if doc in files and files[doc][0] != 'dir':
        sys.exit(f'{deb}: {doc} is a {files[doc][0]}, not a folder')
    source = fields.get('source', package).split()[0]
    out = []
    for key, value in pairs:
        low = key.lower()
        if low == 'version':
            value = version
        elif low == 'maintainer':
            out.append([key, MAINTAINER])
            key, value = 'Original-Maintainer', value
        elif low in ('homepage', 'bugs', 'source', 'original-maintainer'):
            continue
        elif key in RELATIONS:
            value = rewrite_relation(value, names, nv_version, version)
        elif low == 'description':
            value += ('\n .\n Sparky Stereo OS: NVIDIA\'s ' + package + ' ' + nv_version + ' for Debian 12, its files'
                      '\n byte for byte as NVIDIA ships them, for the Maxwell, Pascal and Volta'
                      '\n cards the edition\'s open modules do not run. See README.sparky-stereo.')
        out.append([key, value])
    position = next(i for i, (k, _) in enumerate(out) if k.lower() == 'version')
    out.insert(position + 1, ['Source', f'{source} ({nv_version})'])
    position = next(i for i, (k, _) in enumerate(out) if k.lower() == 'description')
    out[position:position] = [['Homepage', HOMEPAGE], ['Bugs', BUGS]]
    (tree / 'DEBIAN/control').write_text(''.join(f'{k}: {v}\n' for k, v in out))
    docdir = tree / doc.lstrip('/')
    docdir.mkdir(parents=True, exist_ok=True)
    title = f'{package} in Sparky Stereo OS'
    text = Path(readme).read_text().replace('@UNDERLINE@', '=' * len(title)).replace('@PACKAGE@', package) \
        .replace('@NV_VERSION@', nv_version).replace('@VERSION@', version)
    if '@' in re.sub(r'<[^>]*@[^>]*>', '', text):
        sys.exit(f'{readme}: a placeholder is left')
    (docdir / 'README.sparky-stereo').write_text(text)
    entry = Path(changelog).read_text().replace('@SOURCE@', source)
    if not entry.startswith(f'{source} ({version}) '):
        sys.exit(f'{changelog}: the entry is not for {source} {version}')
    with gzip.GzipFile(docdir / f'changelog.Debian.{arch}.gz', 'wb', compresslevel=9, mtime=0) as stream:
        stream.write(entry.encode())
    for path in ours:
        os.chmod(tree / path.lstrip('/'), 0o644)
    # Debian Policy 2.3: "Every package must be accompanied by a verbatim copy of its distribution license(s) in the file
    # /usr/share/doc/PACKAGE/copyright"; NVIDIA's licence, 1.1(d)(ii): distribution "provided that ... this Agreement is
    # provided to each SOFTWARE recipient". NVIDIA's amd64 packages all ship the same file; an i386 twin with it holds a
    # bit-identical file at the same path, as Multi-Arch: same allows (Policy 5.6.34.3).
    added = {}
    if f'{doc}/copyright' not in files:
        shutil.copyfile(copyright_path, docdir / 'copyright')
        os.chmod(docdir / 'copyright', 0o644)
        added[f'{doc}/copyright'] = sha256(Path(copyright_path).read_bytes())
    plan = {plan_pattern(p): PRESERVED for p, v in files.items() if v[0] == 'file'}
    plan.update({plan_pattern(p): PRESERVED_ADDED for p in added})
    (work / 'plan.json').write_text(json.dumps(plan, indent=1, sort_keys=True) + '\n')
    (work / 'nvidia.json').write_text(json.dumps({
        'deb': os.path.basename(deb), 'deb_sha256': sha256(Path(deb).read_bytes()), 'package': package,
        'architecture': arch, 'nv_version': nv_version, 'version': version, 'control': dict(pairs),
        'payload': files, 'maintainer_files': {n: [m, sha256(d)] for n, (m, d) in scripts.items()},
        'names': sorted(names), 'added_nvidia': added,
        'ours': sorted(ours)}, indent=1, sort_keys=True) + '\n')
    print(f'{package}:{arch} staged at {version}: {len(plan)} NVIDIA files kept as NVIDIA ships them')


def verify(built, nvidia_json):
    ref = json.loads(Path(nvidia_json).read_text())
    files, scripts = deb_parts(built)
    package, arch = ref['package'], ref['architecture']
    manifest = f'/usr/share/dpkg-stereo/lc/{package}/{arch}.json'
    problems = []
    for path, (kind, mode, value, owner) in ref['payload'].items():
        got = files.get(path)
        if kind == 'dir':
            if not got or got[0] != 'dir':
                problems.append(f'{path}: folder missing')
            continue
        if got is None:
            problems.append(f'{path}: missing')
        elif (got[0], got[1], got[2]) != (kind, mode, value):
            problems.append(f'{path}: {got[0]} {oct(got[1])} {got[2]}, NVIDIA {kind} {oct(mode)} {value}')
        if got and got[3] != 'root:root':
            problems.append(f'{path}: owner {got[3]}')
    added = sorted(set(p for p, v in files.items() if v[0] != 'dir') - set(ref['payload']))
    if added != sorted(ref['ours'] + [manifest] + list(ref['added_nvidia'])):
        problems.append(f'files added: {added}')
    for path, digest in ref['added_nvidia'].items():
        got = files.get(path)
        if not got or (got[0], got[1], got[2]) != ('file', 0o644, digest):
            problems.append(f'{path}: not NVIDIA\'s copyright file')
    for name, (mode, digest) in ref['maintainer_files'].items():
        if name in ('control', 'md5sums'):
            continue
        got = scripts.get(name)
        if not got or (got[0], sha256(got[1])) != (mode, digest):
            problems.append(f'DEBIAN/{name} differs from NVIDIA\'s')
    extra = sorted(set(scripts) - set(ref['maintainer_files']))
    if extra:
        problems.append(f'maintainer files added: {extra}')
    control = {k: v for k, v in control_paragraph(scripts['control'][1].decode())}
    nvidia = ref['control']
    for key in set(control) | set(nvidia):
        if key.lower() not in CHANGED and control.get(key) != nvidia.get(key):
            problems.append(f'control {key}: {control.get(key)!r}, NVIDIA {nvidia.get(key)!r}')
    for key in RELATIONS:
        want = rewrite_relation(nvidia[key], set(ref['names']), ref['nv_version'], ref['version']) if key in nvidia else None
        if key == 'Breaks':
            want = (want + ', ' if want else '') + LEAN_BREAKS
        if control.get(key) != want:
            problems.append(f'control {key}: {control.get(key)!r}, expected {want!r}')
    expect = {'Maintainer': MAINTAINER, 'Original-Maintainer': nvidia['Maintainer'], 'Homepage': HOMEPAGE, 'Bugs': BUGS}
    for key, want in expect.items():
        if control.get(key) != want:
            problems.append(f'control {key}: {control.get(key)!r}, expected {want!r}')
    if not control.get('Description', '').startswith(nvidia['Description'] + '\n .\n Sparky Stereo OS: '):
        problems.append('control Description: NVIDIA\'s text is not kept before the edition\'s note')
    if control.get('Version') != ref['version'] or control.get('Source', '').split()[1:] != [f'({ref["nv_version"]})']:
        problems.append(f'control version or source: {control.get("Version")} {control.get("Source")}')
    if problems:
        sys.exit(f'{built}:\n  ' + '\n  '.join(problems))
    for path in sorted(ref['payload']):
        kind, mode, value, _ = ref['payload'][path]
        if kind == 'file':
            print(f'{value}  {package}:{arch}  {path}')
    print(f'# {package}:{arch} {ref["version"]}: {sum(v[0] == "file" for v in ref["payload"].values())} NVIDIA files '
          f'identical to {ref["deb"]} ({ref["deb_sha256"]}), maintainer files identical, 3 files of the edition'
          + (', NVIDIA\'s copyright file added' if ref['added_nvidia'] else ''),
          file=sys.stderr)


if __name__ == '__main__':
    command, *args = sys.argv[1:] or ['']
    commands = {'select': (select, 4), 'check-index': (check_index, 4), 'stage': (stage, 8), 'verify': (verify, 2)}
    if command not in commands or len(args) != commands[command][1]:
        sys.exit(__doc__)
    commands[command][0](*args)
