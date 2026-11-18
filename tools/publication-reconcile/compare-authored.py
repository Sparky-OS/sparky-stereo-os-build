#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Compare an accepted compiled package with a source-built successor."""
import argparse
from collections import Counter
import gzip
import hashlib
import json
import lzma
from pathlib import Path
import re
import subprocess
import tarfile
import tempfile


def archive(path):
    result = {}
    proc = subprocess.Popen(['dpkg-deb', '--fsys-tarfile', str(path)], stdout=subprocess.PIPE)
    with tarfile.open(fileobj=proc.stdout, mode='r|') as stream:
        for member in stream:
            name = member.name.removeprefix('./').rstrip('/') or '.'
            data = stream.extractfile(member).read() if member.isfile() else None
            result[name] = {'type': member.type.decode('ascii'), 'mode': member.mode,
                            'uid': member.uid, 'gid': member.gid, 'link': member.linkname, 'data': data}
    if proc.wait():
        raise ValueError('Unreadable archive: ' + str(path))
    return result


def restore(primary, hr):
    manifest = json.loads(next(v['data'] for k, v in primary.items() if '/lc/' in k and k.endswith('.json')))
    restored = {}
    for entry in manifest['files']:
        name = entry['path'].lstrip('/')
        if 'sha256' in entry and name in primary and primary[name]['data'] is not None:
            if hashlib.sha256(primary[name]['data']).hexdigest() != entry['sha256']:
                raise ValueError('Installed payload differs from its manifest: ' + entry['path'])
        if 'sha_hr' not in entry:
            continue
        blob = next(v['data'] for k, v in hr.items() if k.endswith('/' + entry['sha_hr'] + '.xz'))
        data = lzma.decompress(blob)
        if hashlib.sha256(data).hexdigest() != entry['sha_hr']:
            raise ValueError('Authored blob hash differs: ' + entry['path'])
        restored[entry['path'].lstrip('/')] = data
    return manifest, restored


def elf(path):
    symbols = []
    text = subprocess.check_output(['readelf', '--dyn-syms', '--wide', str(path)], text=True)
    for line in text.splitlines():
        fields = line.split()
        if len(fields) < 8 or not fields[0].endswith(':') or fields[6] == 'UND':
            continue
        if fields[4] not in ('GLOBAL', 'WEAK', 'UNIQUE'):
            continue
        symbols.append((fields[7], fields[3], fields[4], fields[5], fields[2] if fields[3] in ('OBJECT', 'TLS') else ''))
    dynamic = subprocess.check_output(['readelf', '--dynamic', '--wide', str(path)], text=True)
    needed = sorted(re.findall(r'\(NEEDED\).*?\[([^\]]+)\]', dynamic))
    notes = subprocess.check_output(['readelf', '--notes', str(path)], text=True)
    build_id = next(iter(re.findall(r'Build ID: ([0-9a-f]+)', notes)), '')
    command = ['readelf', '--wide'] + ['--string-dump=' + section for section in ('.rodata', '.dynstr', '.strtab', '.comment')] + [str(path)]
    run = subprocess.run(command, capture_output=True, check=True)
    strings, fragments, section = [], [], ''
    for line in run.stdout.decode('latin-1').splitlines():
        heading = re.match(r"String dump of section '([^']+)':", line)
        if heading:
            section = heading[1]
        match = re.match(r'\s*\[\s*[0-9a-f]+\]\s+(.*)', line)
        if not match:
            continue
        value = match[1]
        # SHT_STRTAB is compared whole. PROGBITS also contains numeric/QML
        # bytecode data; use strings(1)'s default four-byte threshold there.
        (fragments if section == '.rodata' and len(value) < 4 else strings).append((section, value))
    return {'exports': sorted(symbols), 'needed': needed, 'build_id': build_id, 'strings': strings,
            'short_rodata_fragments': fragments, 'strings_dump': run.stdout, 'strings_diagnostic': run.stderr.decode('latin-1')}


ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('accepted', type=Path)
ap.add_argument('successor', type=Path)
ap.add_argument('--accepted-hr', type=Path, required=True)
ap.add_argument('--successor-hr', type=Path, required=True)
ap.add_argument('--output', type=Path, required=True)
a = ap.parse_args()
a.output.mkdir(parents=True, exist_ok=True)
old, new = archive(a.accepted), archive(a.successor)
oldm, oldauth = restore(old, archive(a.accepted_hr))
newm, newauth = restore(new, archive(a.successor_hr))
failures, rows, binaries = [], [], []
if set(old) != set(new):
    failures.append({'file_list_removed': sorted(set(old)-set(new)), 'file_list_added': sorted(set(new)-set(old))})
with tempfile.TemporaryDirectory() as temporary:
    for index, name in enumerate(sorted(set(old) & set(new))):
        left, right = old[name], new[name]
        if {k:v for k,v in left.items() if k != 'data'} != {k:v for k,v in right.items() if k != 'data'}:
            failures.append({'member_properties': name})
        before, after = left['data'], right['data']
        if before is None:
            continue
        if before.startswith(b'\x7fELF') and after.startswith(b'\x7fELF'):
            paths = [Path(temporary) / f'{index}-{side}' for side in ('old', 'new')]
            for path, data in zip(paths, (before, after)):
                path.write_bytes(data)
            x, y = map(elf, paths)
            for side, value in [('old', x), ('new', y)]:
                (a.output / f'elf-{index}-{side}-strings.txt').write_bytes(value.pop('strings_dump'))
            def normalized(obj, version):
                values = []
                for section, value in obj['strings']:
                    value = value.replace(version, '<PACKAGE_VERSION>')
                    if section == '.comment' and value.startswith('GCC: '):
                        value = '<COMPILER_VERSION>'
                    if obj['build_id']:
                        value = value.replace(obj['build_id'], '<BUILD_ID>')
                    values.append((section, value))
                return Counter(values)
            xs, ys = normalized(x, oldm['version']), normalized(y, newm['version'])
            difference = {'file': name, 'exports_equal': x['exports'] == y['exports'], 'needed_equal': x['needed'] == y['needed'],
                          'strings_equal': xs == ys, 'strings_removed': list((xs-ys).elements()),
                          'strings_added': list((ys-xs).elements()),
                          'short_rodata_removed': list((Counter(x['short_rodata_fragments'])-Counter(y['short_rodata_fragments'])).elements()),
                          'short_rodata_added': list((Counter(y['short_rodata_fragments'])-Counter(x['short_rodata_fragments'])).elements()),
                          'accepted': x, 'successor': y}
            binaries.append(difference)
            if not all(difference[k] for k in ('exports_equal', 'needed_equal', 'strings_equal')):
                failures.append({'elf_interface_or_strings': name})
            continue
        if '/dpkg-stereo/lc/' in name:
            reason = 'Generated payload manifest; versions and binary hashes change'
        elif name.endswith('/changelog.gz'):
            reason = 'New changelog entry; accepted history retained exactly'
            if not gzip.decompress(after).endswith(gzip.decompress(before)):
                failures.append({'changelog_history': name})
        else:
            before, after = oldauth.get(name, before), newauth.get(name, after)
            reason = 'Restored authored bytes equal'
            if before != after:
                failures.append({'authored_content': name})
        rows.append({'file': name, 'reason': reason, 'accepted_sha256': hashlib.sha256(before).hexdigest(),
                     'successor_sha256': hashlib.sha256(after).hexdigest()})
result = {'accepted': str(a.accepted), 'successor': str(a.successor), 'accepted_renderer': oldm.get('renderer'),
          'successor_renderer': newm.get('renderer'), 'member_count': len(old), 'authored_data': rows,
          'elf': binaries, 'failures': failures}
(a.output / 'comparison.json').write_text(json.dumps(result, indent=2) + '\n')
print(f'{len(old)} members; {len(rows)} script/data records; {len(binaries)} ELF files; {len(failures)} differences requiring review')
raise SystemExit(bool(failures))
