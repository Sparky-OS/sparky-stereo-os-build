#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Cross-check an accepted source generation's archives and retained receipts."""
import argparse
from collections import defaultdict
import csv
from functools import lru_cache
import json
from pathlib import Path
import re

from inventory import paragraphs, digest
from reconcile import write_tsv


@lru_cache(maxsize=None)
def sha(path):
    return digest(Path(path))


def control(path):
    return next(row for row in paragraphs(path.read_text()) if 'Version' in row and 'Source' in row)


def checked_path(parent, name):
    if Path(name).name != name or name in ('.', '..'):
        raise ValueError(f'unsafe archive component: {name!r}')
    path = parent / name
    if not path.is_file():
        raise ValueError(f'missing archive: {path}')
    return path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('files', type=Path)
    parser.add_argument('rules', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    rows = list(csv.DictReader(args.files.open(), delimiter='\t'))
    candidates = [r for r in rows if r['decision'] == 'candidate']
    rules = json.loads(args.rules.read_text())
    groups = defaultdict(list)
    for row in candidates:
        groups[(row['source'], row['source_version'])].append(row)
    results, artifacts = [], []
    for (source, version), members in sorted(groups.items()):
        errors, warnings, checked = [], [], {}
        def verify(path, expected=None, size=None):
            actual = sha(str(path))
            if expected and actual != expected:
                errors.append(f'hash mismatch {path}: expected {expected}, actual {actual}')
            if size is not None and path.stat().st_size != int(size):
                errors.append(f'size mismatch {path}')
            checked[str(path)] = actual
        descriptors = [Path(r['stage']) / r['filename'] for r in members if r['kind'] == 'source']
        dsc = descriptors[0]
        relevant_roots = [Path(r['root']) for r in rules if r['decision'] == 'candidate'
                          and r.get('source') in (None, source) and r.get('version') in (None, version)
                          and dsc.is_relative_to(r['root'])]
        stage_root = min(relevant_roots, key=lambda p: len(p.parts))
        allfiles = [p for p in stage_root.rglob('*') if p.is_file() and len(p.relative_to(stage_root).parts) <= 5]
        byname = defaultdict(list)
        for path in allfiles:
            byname[path.name].append(path)
        def locate(name, parent):
            direct = parent / name
            if direct.is_file():
                return direct
            choices = byname[name]
            if len(choices) != 1:
                raise ValueError(f'{source} {version}: ambiguous/missing {name}: {choices}')
            return choices[0]
        fields = control(dsc)
        if fields['Source'] != source or fields['Version'] != version:
            errors.append(f'descriptor identity mismatch: {dsc}')
        verify(dsc)
        for line in fields.get('Checksums-Sha256', '').splitlines():
            if line.strip():
                h, size, name = line.split()
                try:
                    verify(checked_path(dsc.parent, name), h, size)
                except ValueError as exc:
                    errors.append(str(exc))
        records, infos, changes = [], [], []
        for path in allfiles:
            if path.name.endswith('.sparky-build.json'):
                record = json.loads(path.read_text())
                if record.get('source') == source and record.get('version') == version:
                    records.append((path, record))
            elif path.suffix in ('.buildinfo', '.changes'):
                c = control(path)
                src = c['Source'].split()[0]
                if src == source and c['Version'] == version:
                    (infos if path.suffix == '.buildinfo' else changes).append((path, c))
        if not records:
            errors.append('no matching build record')
        if not infos:
            errors.append('no matching buildinfo')
        if not changes:
            errors.append('no matching changes')
        record_names, record_dscs, changes_names = set(), set(), set()
        for path, record in records:
            verify(path)
            if record.get('recipeDirty') is not False or record.get('unrecorded') != []:
                errors.append(f'unclean/incomplete build record: {path}')
            for item in record.get('debs', []) + record.get('files', []):
                try:
                    f = locate(item['name'], path.parent)
                    verify(f, item['sha256'])
                    record_names.add(f.name)
                    if f.suffix == '.dsc':
                        record_dscs.add(str(f))
                except ValueError as exc:
                    errors.append(str(exc))
        if str(dsc) not in record_dscs:
            warnings.append('descriptor/component hashes are bound by stage SHA256SUMS; binary build record does not list descriptor')
        for path, c in infos + changes:
            verify(path)
            for line in c.get('Checksums-Sha256', '').splitlines():
                if line.strip():
                    h, size, name = line.split()
                    try:
                        f = locate(name, path.parent)
                        verify(f, h, size)
                        if path.suffix == '.changes':
                            changes_names.add(name)
                    except ValueError as exc:
                        errors.append(str(exc))
        for row in members:
            path = Path(row['stage']) / row['filename']
            verify(path)
            if row['kind'] == 'binary':
                if path.name not in record_names:
                    errors.append(f'binary is not bound by a matching build record: {path.name}')
                if path.name not in changes_names:
                    errors.append(f'binary is not bound by matching changes: {path.name}')
        manifest_entries = defaultdict(set)
        # Named predecessor exceptions may have their sum at their parent root.
        manifest_roots = {stage_root, stage_root.parent}
        for root in manifest_roots:
            for manifest in root.glob('SHA256SUMS'):
                for line in manifest.read_text().splitlines():
                    match = re.fullmatch(r'([0-9a-f]{64}) [ *](.+)', line)
                    if match:
                        manifest_entries[str(manifest.parent / match[2])].add(match[1])
        for manifest in stage_root.rglob('SHA256SUMS'):
            for line in manifest.read_text().splitlines():
                match = re.fullmatch(r'([0-9a-f]{64}) [ *](.+)', line)
                if match:
                    manifest_entries[str(manifest.parent / match[2])].add(match[1])
        for filename, h in checked.items():
            matches = manifest_entries[filename]
            if h not in matches:
                errors.append(f'not bound by stage SHA256SUMS: {filename}')
            if matches and matches != {h}:
                errors.append(f'conflicting stage checksum entries: {filename}')
            artifacts.append({'source': source, 'version': version, 'path': filename, 'sha256': h,
                              'bytes': Path(filename).stat().st_size})
        results.append({'source': source, 'version': version, 'verdict': 'FAIL' if errors else 'PASS',
                        'descriptor': str(dsc), 'build_records': len(records), 'buildinfo': len(infos),
                        'changes': len(changes), 'checked_files': len(checked), 'warnings': warnings, 'errors': errors})
        print(source, version, 'FAIL' if errors else 'PASS', *errors, sep='\n  ', flush=True)
    args.output.mkdir(exist_ok=True, parents=True)
    (args.output / 'source-metadata.json').write_text(json.dumps(results, indent=2) + '\n')
    write_tsv(args.output / 'source-artifacts.tsv', artifacts, ['source', 'version', 'path', 'sha256', 'bytes'])
    print(f'{sum(r["verdict"] == "PASS" for r in results)}/{len(results)} source metadata sets pass')
    return int(any(r['verdict'] != 'PASS' for r in results))


if __name__ == '__main__':
    raise SystemExit(main())
