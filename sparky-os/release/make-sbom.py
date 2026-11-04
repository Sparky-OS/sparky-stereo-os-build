#!/usr/bin/env python3
"""Write one SPDX 2.3 (JSON) bill of materials for a published repository tree, or for the tree with a round's
cohort laid over it (ORDER 394). Unsigned; signing and publication are the main session's step of a round.

Usage: make-sbom.py --tree TREE [--cohort-list FILE [--cohort-sha256 FILE]] --name NAME --out FILE [--report FILE]
Everything in the document is read from the packages themselves (see supply_chain.py); a fact the packages do
not carry is NOASSERTION in the document and is counted in the report.
"""
import argparse
import hashlib
import json
import re
import subprocess
import sys
import urllib.parse
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import supply_chain as sc

REPO_URL = 'https://repo.sparkyos.org/'
SUITE = 'mashtabba'
CREATORS = ['Tool: sparky-make-sbom-' + sc.TOOL_VERSION, 'Organization: Sparky Stereo OS']
ORIGINATOR = {'debian': 'Debian', 'deb-multimedia': 'deb-multimedia', 'sparkylinux': 'SparkyLinux'}


def spdxid(*parts):
    h = hashlib.sha256('|'.join(parts).encode()).hexdigest()[:10]
    stem = ''.join(c if c.isalnum() or c in '.-' else '-' for c in '-'.join(parts[:3]))
    return 'SPDXRef-%s-%s' % (stem, h)


def purl(name, version, arch):
    q = lambda s: urllib.parse.quote(s, safe='.-_~')
    return 'pkg:deb/sparky-stereo-os/%s@%s?arch=%s&distro=%s' % (q(name), q(version), arch, SUITE)


EMAIL = re.compile(r'[\w.+-]+@[\w-]+(?:\.[\w-]+)+')


def _extracted(lid, v):
    """A licence text as the copyright file gives it, without the e-mail addresses in it (nothing here carries a person's contact)."""
    text, n = EMAIL.subn('<email omitted>', v['text'])
    info = {'licenseId': lid, 'extractedText': text, 'name': v['name']}
    if n:
        info['comment'] = '%d e-mail address(es) in the original text were replaced by "<email omitted>".' % n
    return info


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--tree', required=True, type=Path)
    ap.add_argument('--cohort-list', type=Path)
    ap.add_argument('--cohort-sha256', type=Path, help='sha256sum file for the cohort list\'s files; checked before reading')
    ap.add_argument('--name', required=True)
    ap.add_argument('--out', required=True, type=Path)
    ap.add_argument('--report', type=Path)
    ap.add_argument('--cache', type=Path, help='JSON file of per-file facts, so a rerun does not decompress the pool again')
    ap.add_argument('--created', default=None, help='UTC time for the document (default: now)')
    a = ap.parse_args()

    if a.cohort_sha256:
        r = subprocess.run(['sha256sum', '-c', '--quiet', str(a.cohort_sha256.resolve())], cwd='/', capture_output=True, text=True)
        if r.returncode != 0:
            sys.exit('the cohort files differ from %s:\n%s' % (a.cohort_sha256, r.stdout + r.stderr))
    cache = sc.Cache(a.cache) if a.cache else None
    inv = sc.build_inventory(a.tree, a.cohort_list, SUITE, cache)
    if cache:
        cache.save()
    created = a.created or datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

    refs = {}
    packages, rels, ann_date = [], [], created
    src_ids = {}
    for key in sorted(inv.sources):
        s = inv.sources[key]
        sid = spdxid('Source', key[0], key[1])
        src_ids[key] = sid
        pk = {'SPDXID': sid, 'name': key[0], 'versionInfo': key[1], 'supplier': 'Organization: Sparky Stereo OS',
              'downloadLocation': 'NOASSERTION', 'filesAnalyzed': False, 'licenseConcluded': 'NOASSERTION',
              'licenseDeclared': 'NOASSERTION', 'copyrightText': 'NOASSERTION',
              'externalRefs': [{'referenceCategory': 'PACKAGE-MANAGER', 'referenceType': 'purl',
                                'referenceLocator': purl(key[0], key[1], 'source')}]}
        if s is None:
            pk['comment'] = 'The source package\'s .dsc was not found beside the repository or the cohort.'
        else:
            dsc = Path(s['dsc_path'])
            if dsc.is_relative_to(a.tree):
                pk['downloadLocation'] = REPO_URL + str(dsc.relative_to(a.tree))
            pk['checksums'] = [{'algorithm': 'SHA256', 'checksumValue': s['dsc_sha256']}]
            pk['comment'] = 'The checksum is the .dsc file\'s. Source files named by its Checksums-Sha256: ' + json.dumps(
                [{'name': f['name'], 'sha256': f['sha256']} for f in s['files']], separators=(',', ':'))
            if s['homepage']:
                pk['homepage'] = s['homepage']
        packages.append(pk)

    counts = {'origin': {}, 'licence_format': {}, 'lean_code': 0, 'no_lean_code': 0}
    for p in inv.packages:
        c = p['control']
        sid = spdxid('Pkg', c['Package'], c['Version'], c['Architecture'], p['sha256'])
        p['spdxid'] = sid
        ver = c['Version']
        fn = p['pool_filename']
        pk = {'SPDXID': sid, 'name': c['Package'], 'versionInfo': ver, 'supplier': 'Organization: Sparky Stereo OS',
              'downloadLocation': (REPO_URL + fn) if fn else 'NOASSERTION', 'filesAnalyzed': False,
              'checksums': [{'algorithm': 'SHA256', 'checksumValue': p['sha256']}],
              'licenseConcluded': 'NOASSERTION', 'licenseDeclared': p['licence'] or 'NOASSERTION', 'copyrightText': 'NOASSERTION',
              'summary': c.get('Description', '').split('\n')[0],
              'externalRefs': [{'referenceCategory': 'PACKAGE-MANAGER', 'referenceType': 'purl',
                                'referenceLocator': purl(c['Package'], ver, c['Architecture'])}],
              'attributionTexts': [], 'annotations': []}
        if c.get('Homepage'):
            pk['homepage'] = c['Homepage']
        if p['origin'] in ORIGINATOR:
            pk['originator'] = 'Organization: ' + ORIGINATOR[p['origin']]
        comment = ['architecture %s' % c['Architecture'], 'origin %s: %s' % (p['origin'], p['origin_basis'])]
        if p['original_maintainer']:
            comment.append('original maintainer: %s' % p['original_maintainer'])
        comment.append('licence: %s' % p['licence_format'])
        if not fn:
            comment.append('not yet published: the download location is unknown until the round is sent')
        pk['comment'] = '; '.join(comment)
        lc = p['lc']
        if lc:
            pk['annotations'].append({'annotationType': 'OTHER', 'annotator': CREATORS[0], 'annotationDate': ann_date,
                                      'comment': 'sparky:lean-code ' + json.dumps(lc, sort_keys=True, separators=(',', ':'))})
            counts['lean_code'] += 1
        else:
            counts['no_lean_code'] += 1
        if not pk['annotations']:
            del pk['annotations']
        if not pk['attributionTexts']:
            del pk['attributionTexts']
        packages.append(pk)
        refs.update(p['licence_refs'])
        counts['origin'][p['origin']] = counts['origin'].get(p['origin'], 0) + 1
        fmt = p['licence_format'].split(' ')[0] if not p['licence_format'].startswith('via') else 'via-symlink'
        counts['licence_format'][fmt] = counts['licence_format'].get(fmt, 0) + 1
        rels.append({'spdxElementId': 'SPDXRef-DOCUMENT', 'relationshipType': 'DESCRIBES', 'relatedSpdxElement': sid})
        sk = (p['source'], p['source_version'])
        rels.append({'spdxElementId': sid, 'relationshipType': 'GENERATED_FROM', 'relatedSpdxElement': src_ids[sk]})

    # the namespace is made from the content, so the same inputs always give the same document
    ident = hashlib.sha256('\n'.join(sorted(p['sha256'] + p['filename'] for p in inv.packages)).encode()).hexdigest()
    doc = {
        'spdxVersion': 'SPDX-2.3', 'dataLicense': 'CC0-1.0', 'SPDXID': 'SPDXRef-DOCUMENT', 'name': a.name,
        'documentNamespace': '%ssbom/%s-%s' % (REPO_URL, a.name, ident[:16]),
        'creationInfo': {'created': created, 'creators': CREATORS,
                         'comment': 'Made from the packages themselves: control files, debian/copyright, the Lean Code records and the .dsc files. '
                                    'Unsigned. Notes: ' + ('; '.join(inv.notes) if inv.notes else 'none')},
        'packages': packages, 'relationships': rels,
    }
    if refs:
        doc['hasExtractedLicensingInfos'] = [_extracted(k, v) for k, v in sorted(refs.items())]
    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_text(json.dumps(doc, indent=1, ensure_ascii=False, sort_keys=False) + '\n')
    rep = {'document': str(a.out), 'name': a.name, 'binary_packages': len(inv.packages), 'source_packages': len(inv.sources),
           'sources_without_dsc': sorted('%s %s' % k for k, v in inv.sources.items() if v is None),
           'counts': counts, 'extracted_licence_refs': len(refs), 'notes': inv.notes, 'size_bytes': a.out.stat().st_size,
           'sha256': sc.sha256_file(a.out)}
    if a.report:
        a.report.write_text(json.dumps(rep, indent=1) + '\n')
    print(json.dumps({k: v for k, v in rep.items() if k not in ('notes', 'sources_without_dsc')}, indent=1))


if __name__ == '__main__':
    main()
