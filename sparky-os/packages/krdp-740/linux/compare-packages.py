#!/usr/bin/env python3
"""Compare Debian payloads, relationships and every ELF without executing payloads.

Usage: compare-packages.py NEW_DIRECTORY OLD_DIRECTORY OUTPUT.json
Directories must contain one version of each Package/Architecture pair. Extra old
packages may supply sibling libraries. ELF providers are static evidence: GNU
version requirements, or export candidates in the NEEDED closure, not a claim
about runtime interposition. Unresolved weak imports remain explicitly listed.
"""
import argparse
from collections import defaultdict, deque
from functools import lru_cache
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess
import tarfile
import tempfile

FIELDS = ('Depends', 'Recommends', 'Suggests', 'Provides', 'Breaks', 'Replaces')


def command(*args):
    return subprocess.check_output(args, text=True, errors='replace', env={'PATH': '/usr/sbin:/usr/bin:/sbin:/bin', 'LC_ALL': 'C'})


def sha(data):
    return hashlib.sha256(data).hexdigest()


def control(deb):
    result = {}
    for line in command('dpkg-deb', '-f', str(deb)).splitlines():
        if line.startswith((' ', '\t')):
            result[key] += '\n' + line
        elif ':' in line:
            key, value = line.split(':', 1)
            result[key] = value.strip()
    return result


def relationships(value):
    result = defaultdict(list)
    for group in value.split(','):
        for alternative in group.split('|'):
            clause = ' '.join(alternative.split())
            if not clause:
                continue
            match = re.match(r'([a-z0-9][a-z0-9+.-]*(?::[a-z0-9-]+)?)\b', clause)
            if not match:
                raise ValueError('Unparsed relationship: ' + clause)
            result[match[1]].append(clause)
    return {name: sorted(clauses) for name, clauses in sorted(result.items())}


def inventory(deb, part, directory):
    data = subprocess.check_output(['dpkg-deb', '--fsys-tarfile' if part == 'payload' else '--ctrl-tarfile', str(deb)])
    entries, elfs = {}, {}
    with tarfile.open(fileobj=io.BytesIO(data)) as archive:
        for member in archive:
            content = archive.extractfile(member).read() if member.isfile() else None
            entries[member.name] = dict(type=member.type.decode(), mode=oct(member.mode), uid=member.uid, gid=member.gid, link=member.linkname, sha256=sha(content) if content is not None else None)
            if part == 'payload' and content is not None and content.startswith(b'\x7fELF'):
                path = directory / str(len(elfs))
                path.write_bytes(content)
                elfs[member.name] = path
    return entries, elfs


@lru_cache(maxsize=None)
def elf(path):
    diagnostics = []
    def inspect(option):
        result = subprocess.run(['readelf', '--wide', option, path], text=True, capture_output=True, check=True, env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'})
        if result.stderr.strip():
            diagnostics.append(dict(option=option, message=result.stderr.strip()))
        return result.stdout
    sections = inspect('--section-headers')
    dynamic = inspect('--dynamic')
    notes = inspect('--notes')
    versions = inspect('--version-info')
    symbols = inspect('--dyn-syms')
    section_types = dict(re.findall(r'\]\s+(\S+)\s+(\S+)', sections))
    # Separate debug ELFs retain PT_INTERP with a NOBITS .interp section.
    # Binutils reports that missing payload while still reading the debug ELF.
    for diagnostic in diagnostics:
        if diagnostic['message'] != 'readelf: Error: Unable to find program interpreter name' or section_types.get('.interp') != 'NOBITS':
            raise ValueError(f'Unexplained ELF diagnostic for {path}: {diagnostic}')
    needed = re.findall(r'\(NEEDED\).*\[([^]]+)\]', dynamic)
    sonames = re.findall(r'\(SONAME\).*\[([^]]+)\]', dynamic)
    search_paths = [part for entry in re.findall(r'\((?:RUNPATH|RPATH)\).*\[([^]]+)\]', dynamic) for part in entry.split(':')]
    ids = re.findall(r'Build ID: (\w+)', notes)
    version_libraries = {}
    library = None
    for line in versions.splitlines():
        match = re.search(r'File: (\S+)', line)
        if match:
            library = match[1]
        match = re.search(r'Name: (\S+).*Version: (\d+)', line)
        if match and library:
            version_libraries[int(match[2])] = library
    imports, exports = [], set()
    for line in symbols.splitlines():
        fields = line.split()
        if len(fields) < 8 or not fields[0].rstrip(':').isdigit():
            continue
        name = fields[7]
        base, _, version = name.partition('@')
        version = version.lstrip('@')
        if fields[6] != 'UND':
            if fields[4] in ('GLOBAL', 'WEAK', 'UNIQUE') and fields[5] in ('DEFAULT', 'PROTECTED') and ('@' not in name or '@@' in name):
                exports.add(base)
            continue
        index = re.search(r'\((\d+)\)\s*$', line)
        declared = version_libraries.get(int(index[1])) if index else None
        if version and not declared:
            raise ValueError(f'No GNU provider for {name} in {path}')
        imports.append(dict(symbol=base, version=version or None, binding=fields[4], declaredLibrary=declared))
    return dict(needed=needed, soname=sonames[0] if sonames else None, buildId=ids[0] if ids else None, imports=imports, exports=exports, sectionTypes=section_types, diagnostics=diagnostics, searchPaths=search_paths)


def library_cache():
    result = {}
    for line in command('ldconfig', '-p').splitlines():
        match = re.match(r'\s*(\S+) .* => (\S+)', line)
        if match:
            result.setdefault(match[1], match[2])
    return result


def load(directory, temporary):
    packages = {}
    for number, deb in enumerate(sorted(directory.glob('*.deb'))):
        fields = control(deb)
        key = (fields['Package'], fields['Architecture'])
        if key in packages:
            raise ValueError('Duplicate package/architecture: ' + str(key))
        target = temporary / str(number)
        target.mkdir(parents=True)
        payload, paths = inventory(deb, 'payload', target)
        ctrl, _ = inventory(deb, 'control', target)
        packages[key] = dict(file=deb.name, sha256=sha(deb.read_bytes()), fields=fields, payload=payload, control=ctrl, paths=paths)
    if not packages:
        raise ValueError('No packages in ' + str(directory))
    return packages


def analyze(packages, system):
    local, runtime_ids, original_paths = {}, {}, {}
    for package in packages.values():
        for original, path in package['paths'].items():
            info = elf(str(path))
            original_paths[str(path)] = '/' + original.removeprefix('./')
            if '/.build-id/' not in original:
                local.setdefault(Path(original).name, str(path))
                if info['soname']:
                    local[info['soname']] = str(path)
                if info['buildId']:
                    runtime_ids[info['buildId']] = original
    def resolve(name, requester):
        if name in local:
            return local[name]
        origin = str(Path(original_paths.get(requester, requester)).parent)
        for directory in elf(requester)['searchPaths']:
            directory = directory.replace('${ORIGIN}', origin).replace('$ORIGIN', origin)
            candidate = Path(directory) / name
            if candidate.is_file():
                return str(candidate)
        return system.get(name)
    for package in packages.values():
        package['elf'] = {}
        for original, path in package['paths'].items():
            info = elf(str(path))
            closure, missing = {}, []
            queue = deque((name, str(path)) for name in info['needed'])
            while queue:
                name, requester = queue.popleft()
                if name in closure or name in missing:
                    continue
                resolved = resolve(name, requester)
                if not resolved:
                    missing.append(name)
                    continue
                dependency = elf(resolved)
                closure[name] = dependency['exports']
                queue.extend((name, resolved) for name in dependency['needed'])
            imports = []
            for entry in info['imports']:
                entry = dict(entry)
                entry['exportCandidates'] = sorted(name for name, symbols in closure.items() if entry['symbol'] in symbols) if not entry['declaredLibrary'] else []
                imports.append(entry)
            imports.sort(key=lambda value: (value['symbol'], value['version'] or '', value['binding']))
            by_library = defaultdict(list)
            for entry in imports:
                providers = [entry['declaredLibrary']] if entry['declaredLibrary'] else entry['exportCandidates'] or ['<unresolved-' + entry['binding'].lower() + '>']
                for name in providers:
                    by_library[name].append(entry['symbol'] + ('@' + entry['version'] if entry['version'] else ''))
            logical = original
            if '/.build-id/' in original and info['buildId'] in runtime_ids:
                logical = 'debug-for:' + runtime_ids[info['buildId']]
            if logical in package['elf']:
                raise ValueError('Duplicate logical ELF: ' + logical)
            package['elf'][logical] = dict(path=original, needed=info['needed'], soname=info['soname'], buildId=info['buildId'], undefinedDynamicSymbols=imports, undefinedByLibrary={name: sorted(symbols) for name, symbols in sorted(by_library.items())}, missingClosureLibraries=sorted(missing), sectionTypes=info['sectionTypes'], inspectionDiagnostics=info['diagnostics'])


def compare_maps(old, new):
    return [dict(path=path, state='added' if path not in old else 'removed' if path not in new else 'identical' if old[path] == new[path] else 'changed', old=old.get(path), new=new.get(path)) for path in sorted(old.keys() | new.keys())]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('new', type=Path)
    parser.add_argument('old', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='elf-package-audit-') as tmp:
        old = load(args.old, Path(tmp) / 'old')
        new = load(args.new, Path(tmp) / 'new')
        system = library_cache()
        analyze(old, system)
        analyze(new, system)
        rows = []
        for key, candidate in sorted(new.items()):
            if key not in old:
                raise ValueError('No predecessor Package/Architecture: ' + str(key))
            previous = old[key]
            row = dict(package=key[0], architecture=key[1], oldFile=previous['file'], newFile=candidate['file'], oldVersion=previous['fields']['Version'], newVersion=candidate['fields']['Version'], oldSha256=previous['sha256'], newSha256=candidate['sha256'])
            for part in ('payload', 'control'):
                row[part] = compare_maps(previous[part], candidate[part])
            row['relationships'] = {}
            for field in FIELDS:
                a, b = previous['fields'].get(field, ''), candidate['fields'].get(field, '')
                row['relationships'][field] = dict(old=a, new=b, byPackage=compare_maps(relationships(a), relationships(b)))
            row['elf'] = compare_maps(previous['elf'], candidate['elf'])
            for entry in row['elf']:
                a, b = entry['old'] or {}, entry['new'] or {}
                entry['neededAdded'] = sorted(set(b.get('needed', [])) - set(a.get('needed', [])))
                entry['neededRemoved'] = sorted(set(a.get('needed', [])) - set(b.get('needed', [])))
                entry['undefinedLibraryChanges'] = [change for change in compare_maps(a.get('undefinedByLibrary', {}), b.get('undefinedByLibrary', {})) if change['state'] != 'identical']
            rows.append(row)
        result = dict(format='debian-elf-comparison/1', providerMethod='GNU verneed library for versioned imports; static export candidates in transitive NEEDED closure using cohort siblings, object RUNPATH/RPATH and ldconfig cache for unversioned imports; no payload executed; no runtime interposition claim', packages=rows)
        args.output.write_text(json.dumps(result, indent=2) + '\n')
        for row in rows:
            changes = [entry['path'] for entry in row['elf'] if entry['neededAdded'] or entry['neededRemoved'] or entry['undefinedLibraryChanges']]
            print(row['package'], 'ELFs:', len(row['elf']), 'import changes:', ', '.join(changes) or 'none')


if __name__ == '__main__':
    main()
