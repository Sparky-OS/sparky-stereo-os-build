#!/usr/bin/env python3
"""Write one in-toto Statement (SLSA Provenance v1 predicate) per source package build in a repository tree, or in
the tree with a round's cohort laid over it (ORDER 394). Unsigned statements; signing is the main session's step.

Usage: make-provenance.py --tree TREE [--cohort-list FILE [--cohort-sha256 FILE]] [--buildinfo-dir DIR ...]
                          --recipes-dir sparky-os/packages [--recipes-dir sparky-os/upstream] --out-dir DIR [--report FILE]

One statement covers every .deb one source package version built for one architecture (the architecture:all
packages go with the amd64 build). It records only what the files carry; what SLSA asks for and nothing records is
written to the gap report per recipe, never filled in.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import urllib.parse
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import supply_chain as sc

BUILD_REPO = 'https://github.com/Sparky-OS/sparky-stereo-os-build'
DOC = BUILD_REPO + '/blob/main/sparky-os/release/SUPPLY-CHAIN.md'
BUILD_TYPE = DOC + '#build-type-debian-source-lean-code-v1'
BUILDER_ID = DOC + '#builder-lane-container'
PREDICATE_TYPE = 'https://slsa.dev/provenance/v1'
STATEMENT_TYPE = 'https://in-toto.io/Statement/v1'


def buildinfo_index(dirs):
    """sha256 of a listed .deb or .dsc -> parsed .buildinfo, from files found below the directories (no symlinks followed)."""
    idx, seen = {}, 0
    for d in dirs:
        for root, _, files in os.walk(d, followlinks=False):
            for fn in files:
                if not fn.endswith('.buildinfo'):
                    continue
                path = Path(root) / fn
                try:
                    bi = sc.parse_deb822(sc.strip_pgp(path.read_text(encoding='utf-8', errors='replace')))[0]
                except sc.ReadError:
                    continue
                seen += 1
                bi['_path'], bi['_sha256'] = str(path), sc.sha256_file(path)
                for line in bi.get('Checksums-Sha256', '').split('\n'):
                    f = line.split()
                    if len(f) == 3:
                        idx[f[0]] = bi
    return idx, seen


def recipe_index(recipe_roots):
    """source package name -> recipe directory, from directory names and the changelog files a recipe keeps,
    below each root (sparky-os/packages, sparky-os/upstream)."""
    idx = {}
    for root in recipe_roots:
        for d in sorted(Path(root).iterdir()):
            if not d.is_dir():
                continue
            idx.setdefault(d.name, d)
            for cl in list(d.glob('changelog*')) + list(d.glob('debian/changelog')):
                try:
                    m = re.match(r'^(\S+) \(', cl.read_text(errors='replace'))
                except OSError:
                    continue
                if m:
                    idx.setdefault(m.group(1), d)
    return idx


def recipe_facts(d):
    pins = False
    for f in d.rglob('*'):
        if f.is_file() and f.suffix in ('.sh', '') and f.stat().st_size < 400000:
            try:
                if re.search(r'@sha256:[0-9a-f]{64}', f.read_text(errors='replace')):
                    pins = True
                    break
            except OSError:
                pass
    return {'pins_image_digest': pins}


def build_deps(bi):
    out = []
    origin = bi.get('Build-Origin', 'unknown').lower()
    for line in bi.get('Installed-Build-Depends', '').replace(',', '').split('\n'):
        m = re.match(r'^\s*(\S+)\s+\(=\s*(\S+)\)', line)
        if not m:
            continue
        name, ver = m.groups()
        arch = None
        if ':' in name:
            name, arch = name.split(':', 1)
        q = lambda s: urllib.parse.quote(s, safe='.-_~')
        uri = 'pkg:deb/%s/%s@%s' % (q(origin), q(name), q(ver)) + ('?arch=' + arch if arch else '')
        out.append({'uri': uri, 'annotations': {'role': 'installed-build-depends'}})
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--tree', required=True, type=Path)
    ap.add_argument('--cohort-list', type=Path)
    ap.add_argument('--cohort-sha256', type=Path)
    ap.add_argument('--buildinfo-dir', action='append', default=[], type=Path)
    ap.add_argument('--recipes-dir', required=True, action='append', type=Path, help='a folder of recipe folders (repeat for sparky-os/packages and sparky-os/upstream)')
    ap.add_argument('--out-dir', required=True, type=Path)
    ap.add_argument('--report', type=Path)
    ap.add_argument('--bundle', type=Path, help='also write every statement, one per line, to this .jsonl file (the in-toto bundle convention)')
    ap.add_argument('--cache', type=Path)
    a = ap.parse_args()

    if a.cohort_sha256:
        r = subprocess.run(['sha256sum', '-c', '--quiet', str(a.cohort_sha256.resolve())], cwd='/', capture_output=True, text=True)
        if r.returncode != 0:
            sys.exit('the cohort files differ from %s:\n%s' % (a.cohort_sha256, r.stdout + r.stderr))
    cache = sc.Cache(a.cache) if a.cache else None
    inv = sc.build_inventory(a.tree, a.cohort_list, 'mashtabba', cache)
    if cache:
        cache.save()
    bidx, bseen = buildinfo_index(a.buildinfo_dir)
    recipes = recipe_index(a.recipes_dir)
    a.out_dir.mkdir(parents=True, exist_ok=True)

    groups = {}
    for p in inv.packages:
        arch = p['control']['Architecture']
        if arch != 'all':
            groups.setdefault((p['source'], p['source_version'], arch), []).append(p)
    for p in inv.packages:
        if p['control']['Architecture'] == 'all':
            k = (p['source'], p['source_version'], 'amd64')
            if k not in groups:
                alts = [g for g in groups if g[:2] == k[:2]]
                k = alts[0] if alts else (p['source'], p['source_version'], 'all')
            groups.setdefault(k, []).append(p)

    gaps, written, total_subjects, lines = {}, [], 0, []
    for (src, sver, barch), pk in sorted(groups.items()):
        s = inv.sources.get((src, sver))
        rdir = recipes.get(src)
        bi = next((bidx[p['sha256']] for p in pk if p['sha256'] in bidx), None)
        g = ['recipe-commit', 'builder-image-digest', 'build-start-time', 'invocation-id']
        if rdir is None:
            g.append('recipe-unresolved')
        if bi is None:
            g += ['build-environment', 'build-dependencies', 'build-finish-time']
        if s is None:
            g.append('source-dsc-missing')
        key = '/'.join(rdir.parts[-3:]) if rdir else 'unresolved:' + src
        e = gaps.setdefault(key, {'recipe': ('/'.join(rdir.parts[-3:]) if rdir else None),
                                  'pins_image_digest': recipe_facts(rdir)['pins_image_digest'] if rdir else None,
                                  'sources': set(), 'statements': 0, 'with_buildinfo': 0, 'gaps': set()})
        e['sources'].add(src)
        e['statements'] += 1
        e['with_buildinfo'] += 1 if bi else 0
        e['gaps'].update(g)

        resolved = []
        if s:
            resolved.append({'name': Path(s['dsc_path']).name, 'digest': {'sha256': s['dsc_sha256']},
                             'annotations': {'role': 'source-control-file'}})
            for f in s['files']:
                resolved.append({'name': f['name'], 'digest': {'sha256': f['sha256']}, 'annotations': {'role': 'source-file'}})
        if bi:
            resolved += build_deps(bi)
        lcs = [p['lc'] for p in pk if p['lc']]
        internal = {
            'leanCode': {'packagesWithRecord': len(lcs), 'packages': len(pk),
                         'renderers': sorted({l['renderer'] for l in lcs if l['renderer']}),
                         'rendererSha256': sorted({l['renderer_sha256'] for l in lcs if l['renderer_sha256']}),
                         'hrPackages': sorted({l['hr_package'] for l in lcs if l['hr_package']}),
                         'filesByStatus': {st: sum(l['files'].get(st, 0) for l in lcs) for st in sorted({k for l in lcs for k in l['files']})}},
            'buildinfo': {'present': bi is not None},
        }
        if bi:
            internal['buildinfo'].update({'environment': bi.get('Environment', '').strip().split('\n'),
                                          'buildOrigin': bi.get('Build-Origin'), 'buildArchitecture': bi.get('Build-Architecture')})
        ext = {'source': {'name': src, 'version': sver}, 'architecture': barch}
        if rdir:
            ext['recipe'] = {'repository': BUILD_REPO, 'path': '/'.join(rdir.parts[-3:])}
        run = {'builder': {'id': BUILDER_ID}}
        if bi:
            run['metadata'] = {'finishedOn': _utc(bi.get('Build-Date'))}
            run['byproducts'] = [{'name': Path(bi['_path']).name, 'digest': {'sha256': bi['_sha256']}, 'annotations': {'role': 'buildinfo'}}]
        run['metadata'] = {k: v for k, v in run.get('metadata', {}).items() if v}
        if not run['metadata']:
            del run['metadata']
        stmt = {
            '_type': STATEMENT_TYPE,
            'subject': [{'name': p['filename'], 'digest': {'sha256': p['sha256']}} for p in sorted(pk, key=lambda p: p['filename'])],
            'predicateType': PREDICATE_TYPE,
            'predicate': {'buildDefinition': {'buildType': BUILD_TYPE, 'externalParameters': ext, 'internalParameters': internal,
                                              'resolvedDependencies': resolved},
                          'runDetails': run},
        }
        total_subjects += len(pk)
        name = urllib.parse.quote('%s_%s_%s' % (src, sver, barch), safe='.-_~+') + '.intoto.json'
        (a.out_dir / name).write_text(json.dumps(stmt, indent=1) + '\n')
        written.append(name)
        lines.append(json.dumps(stmt, separators=(',', ':'), sort_keys=True))

    if a.bundle:
        a.bundle.write_text('\n'.join(lines) + '\n')
    rep = {'statements': len(written), 'subjects': total_subjects, 'binary_packages': len(inv.packages),
           'buildinfo_files_read': bseen, 'statements_with_buildinfo': sum(e['with_buildinfo'] for e in gaps.values()),
           'recipes_resolved': sum(1 for k in gaps if not k.startswith('unresolved:')),
           'sources_without_recipe': sorted(s for k, e in gaps.items() if k.startswith('unresolved:') for s in e['sources']),
           'gaps_by_recipe': {k: {**e, 'sources': sorted(e['sources']), 'gaps': sorted(e['gaps'])} for k, e in sorted(gaps.items())},
           'notes': inv.notes}
    if a.report:
        a.report.write_text(json.dumps(rep, indent=1) + '\n')
    print(json.dumps({k: v for k, v in rep.items() if k not in ('gaps_by_recipe', 'notes', 'sources_without_recipe')}, indent=1))


def _utc(date):
    """RFC 2822 Build-Date to the RFC 3339 form SLSA's Timestamp uses."""
    if not date:
        return None
    from email.utils import parsedate_to_datetime
    from datetime import timezone
    return parsedate_to_datetime(date).astimezone(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')


if __name__ == '__main__':
    main()
