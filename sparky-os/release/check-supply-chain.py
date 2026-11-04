#!/usr/bin/env python3
"""Validate the bill of materials and the provenance statements (ORDER 394) with the standards' own tools.

  check-supply-chain.py sbom FILE.spdx.json [--tree TREE]
      The SPDX project's validator (spdx-tools, tools-python) parses and validates the document against SPDX 2.3.
      With --tree, every package's sha256 is checked against the file in the tree and every package the tree's
      Packages files list must be in the document.
  check-supply-chain.py provenance DIR [--tree TREE]
      Each *.intoto.json is checked as an in-toto Statement v1 (in-toto's attestation library) and its predicate is
      parsed strictly as SLSA Provenance v1 (in-toto's generated protobuf: an unknown field is an error).
      With --tree, each subject's sha256 must be the pool file of that name.
      With --require-recorded (optionally limited by --only-source NAME, repeatable), each such statement must also
      carry what a build leaves since ORDER 394b: the build repository's commit, the builder image, the invocation id
      and the start and finish times; a statement without them is a problem, not a gap.
Exit 0 only when nothing is wrong; every problem is printed.
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import supply_chain as sc


def tree_files(tree):
    return {Path(fn).name: (fn, sha) for fn, sha in sc.read_packages_index(tree).items()}


def check_sbom(path, tree):
    from spdx_tools.spdx.parser.error import SPDXParsingError
    from spdx_tools.spdx.parser.parse_anything import parse_file
    from spdx_tools.spdx.validation.document_validator import validate_full_spdx_document
    problems = []
    try:
        doc = parse_file(str(path))
    except SPDXParsingError as e:
        return ['parse: ' + ' | '.join(e.get_messages())]
    for m in validate_full_spdx_document(doc):
        problems.append('validate: %s (%s)' % (m.validation_message, m.context.full_element if m.context else ''))
    if doc.creation_info.spdx_version != 'SPDX-2.3':
        problems.append('version: %s, not SPDX-2.3' % doc.creation_info.spdx_version)
    if tree:
        tf = tree_files(tree)
        seen = set()
        for p in doc.packages:
            loc = str(p.download_location)
            fn = loc.rsplit('/', 1)[-1]
            if fn.endswith('.deb') and p.checksums:
                if fn not in tf:
                    problems.append('tree: %s is not in the tree\'s Packages files' % fn)
                elif tf[fn][1] != p.checksums[0].value:
                    problems.append('tree: %s sha256 %s differs from the index %s' % (fn, p.checksums[0].value, tf[fn][1]))
                seen.add(fn)
        for fn in sorted(set(tf) - seen):
            problems.append('tree: %s is listed by the tree but missing from the document' % fn)
    return problems


def check_recorded(path, d):
    pred = d.get('predicate') or {}
    rd_ = pred.get('runDetails') or {}
    meta = rd_.get('metadata') or {}
    deps = (pred.get('buildDefinition') or {}).get('resolvedDependencies') or []
    out = []
    if not any((x.get('annotations') or {}).get('role') == 'recipe-repository' and (x.get('digest') or {}).get('gitCommit') for x in deps):
        out.append('no build repository commit in resolvedDependencies')
    if not any((x.get('digest') or {}).get('sha256') for x in (rd_.get('builder') or {}).get('builderDependencies') or []):
        out.append('no builder image digest in runDetails.builder.builderDependencies')
    for field in ('invocationId', 'startedOn', 'finishedOn'):
        if not meta.get(field):
            out.append('no runDetails.metadata.' + field)
    return ['%s: recorded fact missing: %s' % (path.name, m) for m in out]


def check_statement(path, files, require=None):
    from google.protobuf import json_format
    from in_toto_attestation.predicates.provenance.v1 import provenance_pb2
    from in_toto_attestation.v1.statement import Statement
    problems = []
    try:
        d = json.loads(path.read_text())
    except ValueError as e:
        return ['%s: not JSON: %s' % (path.name, e)]
    if d.get('_type') != 'https://in-toto.io/Statement/v1':
        problems.append('%s: _type is %r' % (path.name, d.get('_type')))
    if d.get('predicateType') != 'https://slsa.dev/provenance/v1':
        problems.append('%s: predicateType is %r' % (path.name, d.get('predicateType')))
    try:
        from in_toto_attestation.v1 import statement_pb2
        pb = statement_pb2.Statement()
        json_format.ParseDict(d, pb, ignore_unknown_fields=False)
        Statement.copy_from_pb(pb).validate()
    except Exception as e:
        problems.append('%s: statement: %s' % (path.name, e))
    pred = d.get('predicate') or {}
    try:
        json_format.ParseDict(pred, provenance_pb2.Provenance(), ignore_unknown_fields=False)
    except json_format.ParseError as e:
        problems.append('%s: predicate: %s' % (path.name, e))
    bd, rd_ = pred.get('buildDefinition') or {}, pred.get('runDetails') or {}
    for field, val in (('buildDefinition.buildType', bd.get('buildType')), ('buildDefinition.externalParameters', bd.get('externalParameters')),
                       ('runDetails.builder.id', (rd_.get('builder') or {}).get('id'))):
        if not val:
            problems.append('%s: SLSA Build L1 requires %s' % (path.name, field))
    if require is not None:
        name = ((bd.get('externalParameters') or {}).get('source') or {}).get('name')
        if not require or name in require:
            problems += check_recorded(path, d)
    if files is not None:
        for s in d.get('subject', []):
            n = s.get('name')
            if n not in files:
                problems.append('%s: subject %s is not in the tree' % (path.name, n))
            elif files[n][1] != s.get('digest', {}).get('sha256'):
                problems.append('%s: subject %s sha256 differs from the tree\'s index' % (path.name, n))
    return problems


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('kind', choices=('sbom', 'provenance'))
    ap.add_argument('target', type=Path)
    ap.add_argument('--tree', type=Path)
    ap.add_argument('--require-recorded', action='store_true', help='provenance: statements must carry the build record facts')
    ap.add_argument('--only-source', action='append', default=[], help='with --require-recorded: only statements of this source package')
    a = ap.parse_args()
    if a.kind == 'sbom':
        problems = check_sbom(a.target, a.tree)
        n = 1
    else:
        files = tree_files(a.tree) if a.tree else None
        stmts = sorted(a.target.glob('*.intoto.json'))
        if not stmts:
            sys.exit('no *.intoto.json files in %s' % a.target)
        require = set(a.only_source) if a.require_recorded else None
        problems = [p for s in stmts for p in check_statement(s, files, require)]
        n = len(stmts)
    for p in problems:
        print('FAIL', p)
    print('%s: %d document(s), %d problem(s)' % (a.kind, n, len(problems)))
    sys.exit(1 if problems else 0)


if __name__ == '__main__':
    main()
