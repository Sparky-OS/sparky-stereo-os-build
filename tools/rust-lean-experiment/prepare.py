#!/usr/bin/env python3
"""Prepare checked Rust source forms, without building or measuring the toolchain.

Run inside the named compiler container with the pinned Lean toolkit on PYTHONPATH.
The input is an extracted, patched Debian source. Only Rust inputs change.
"""
from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import replace
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time

from lean import VERSION, core, lang_rust, project, source_tree

VERSION_ID = 'order541-source-v1'
EXCLUDED = {'.git', '.pc', '.sparky-lc', 'debian'}
FIXTURES = {'tests', 'test_data', 'test-data', 'benches', 'examples'}


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def atomic_json(path, value):
    tmp = path.with_suffix(path.suffix + '.partial')
    tmp.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
    tmp.replace(path)


def space(path, needed=0, floor_gib=2):
    free = shutil.disk_usage(path).free
    threshold = (floor_gib + 5) * 1024**3 + needed
    if free < threshold:
        raise RuntimeError(f'space guard: {free} bytes free at {path}, need {threshold}; free scratch before retrying')
    return free


def entries(root):
    for base, dirs, files in os.walk(root, followlinks=False):
        dirs[:] = sorted(d for d in dirs if d not in EXCLUDED)
        for name in sorted(files):
            p = Path(base) / name
            if p.suffix == '.rs' and not p.is_symlink():
                yield p.relative_to(root).as_posix()


def owner(root, name):
    p = Path(name).parent
    while True:
        if (root / p / 'Cargo.toml').is_file():
            return p.as_posix()
        if p == Path('.'):
            return None
        p = p.parent


def doc_policy(root, names):
    """Conservative candidates; the actual build, not this scan, qualifies form C."""
    reasons = {}
    owners = {n: owner(root, n) for n in names}
    for n in names:
        crate = owners[n]
        if crate is None or any(p in FIXTURES for p in Path(n).parts):
            continue
        try:
            code = lang_rust.code_text((root / n).read_text(), literals=False)
        except (ValueError, UnicodeError):
            continue
        why = []
        if re.search(r'\b(?:deny|forbid)\s*\([^)]*missing_docs', code):
            why.append(f'{n}: deny/forbid(missing_docs)')
        if re.search(r'#\s*!?\s*\[\s*doc\s*=\s*include_str\s*!', code):
            why.append(f'{n}: doc = include_str! consumer')
        if re.search(r'\b(?:Parser|Args|Subcommand|ValueEnum|Display|Error)\b', code) and re.search(
                r'\b(?:clap|displaydoc|doc_comment)\b', code):
            why.append(f'{n}: documentation-consuming derive or macro requires build review')
        if re.search(r'\b(?:doc_comment|docinclude)\s*!', code):
            why.append(f'{n}: documentation macro')
        if re.search(r'\brustc_queries\s*!', code):
            why.append(f'{n}: rustc_queries! reads docs and generates replacement attributes when absent')
        if why:
            reasons.setdefault(crate, []).extend(why)
    return owners, reasons


def render_c(text):
    spans = [replace(s, kind=core.COMMENT, why='')
             if s.kind == core.KEEP and 'doc comment' in s.why
             and not core.is_notice(text[s.start:s.end]) else s
             for s in lang_rust.lex(text)]
    return core.render(text, spans, lang_rust.joiner, keep_empty_after=lang_rust.keep_empty_after,
                       collapse_blank=False, drop_lines=True).text


def without_doc_attributes(stream):
    """Filter doc attributes from rustc's token listing, preserving every other token.

    rustc expands comment docs into attributes. Explicit #[doc] remains in the
    source byte-for-byte; this comparison excludes it on both sides as well.
    """
    out, i = [], 0
    while i < len(stream):
        if stream[i].startswith('P\t#\t'):
            j = i + 1
            if j < len(stream) and stream[j].startswith('P\t!\t'):
                j += 1
            if stream[j:j+2] == ['G\t[', 'I\tdoc']:
                k, depth = j + 1, 1
                while k < len(stream) and depth:
                    if stream[k] == 'G\t[':
                        depth += 1
                    elif stream[k] == 'G\t]':
                        depth -= 1
                    k += 1
                if depth:
                    raise RuntimeError('incomplete doc attribute in compiler token output')
                i = k
                continue
        out.append(stream[i])
        i += 1
    return out


def assert_tokens(a, b, c):
    if a != b:
        raise RuntimeError('form B changes compiler tokens')
    if without_doc_attributes(a) != without_doc_attributes(c):
        raise RuntimeError('form C changes tokens beyond doc attributes')


def inventory(root):
    rows = []
    for base, dirs, files in os.walk(root, followlinks=False):
        dirs[:] = sorted(dirs)
        for name in sorted(files + [d for d in dirs if (Path(base) / d).is_symlink()]):
            p = Path(base) / name
            rel = p.relative_to(root).as_posix()
            if p.is_symlink():
                rows.append({'path': rel, 'link': os.readlink(p)})
            else:
                raw = p.read_bytes()
                rows.append({'path': rel, 'mode': p.stat().st_mode & 0o7777,
                             'bytes': len(raw), 'sha256': sha(raw)})
    rows.sort(key=lambda r: r['path'])
    return {'sha256': sha(json.dumps(rows, sort_keys=True, separators=(',', ':')).encode()),
            'files': rows, 'bytes': sum(r.get('bytes', 0) for r in rows)}


def checksum_update(root, changes):
    out = []
    for path in sorted(root.rglob('.cargo-checksum.json')):
        if '.pc' in path.relative_to(root).parts:
            continue
        obj = json.loads(path.read_text())
        count = 0
        for name, digest in obj.get('files', {}).items():
            rel = (path.parent / name).relative_to(root).as_posix()
            if rel in changes:
                old, new = changes[rel]
                if digest != old:
                    raise RuntimeError(f'{path}: checksum for {name} does not name the authored bytes')
                obj['files'][name] = new
                count += 1
        if count:
            path.write_text(json.dumps(obj, sort_keys=True) + '\n')
            out.append({'path': path.relative_to(root).as_posix(), 'entries': count})
    return out


def prepare(authored, output, batch=80):
    if VERSION != '0.1.29':
        raise RuntimeError(f'need lean 0.1.29, found {VERSION}')
    compiler = subprocess.check_output([lang_rust.rustc(), '-vV'], text=True)
    if 'release: 1.99.1\n' not in compiler:
        raise RuntimeError('qualification needs the named rustc 1.99.1 lexer')
    if output.exists():
        raise RuntimeError('output already exists; inspect or remove the unfinished output explicitly')
    space(authored, sum(p.stat().st_size for p in authored.rglob('*') if p.is_file()) * 2)
    output.mkdir()
    print('Inventorying authored source', flush=True)
    baseline = inventory(authored)
    names = sorted(entries(authored))
    print(f'Classifying source readers of {len(names)} Rust files', flush=True)
    left = source_tree.rust_readers(authored, names)
    print('Classifying include_str!/include_bytes! readers', flush=True)
    read_data = project.read_as_data({'/' + n: (authored / n).read_bytes() for n in names},
                                     ('/' + n for n in names))
    print('Classifying documentation consumers', flush=True)
    owners, doc_reasons = doc_policy(authored, names)
    print('Copying disposable B and C sources', flush=True)
    for form in ('B', 'C'):
        shutil.copytree(authored, output / form, symlinks=True)
    rows, changes, last_guard = {}, {'B': {}, 'C': {}}, 0.0
    for offset in range(0, len(names), batch):
        if time.monotonic() - last_guard >= 5:
            space(output)
            last_guard = time.monotonic()
        prepared, texts = [], []
        for n in names[offset:offset+batch]:
            raw = (authored / n).read_bytes()
            reason = left.get(n) or read_data.get('/' + n)
            if any(p in FIXTURES for p in Path(n).parts) or n.startswith('src/doc/'):
                reason = reason or 'fixture or documentation source: authored consumer, outside nocheck build'
            try:
                a = raw.decode('utf-8')
                if '\r' in a:
                    reason = reason or 'carriage returns: no qualified adapter'
                reason = reason or lang_rust.refuse(a)
                if reason:
                    rows[n] = {'left': reason, 'bytes': len(raw)}
                    continue
                b = project.render_text(a, 'rust', None, None, None, pointer=False)[0]
                c = b if owners[n] in doc_reasons else render_c(a)
            except (UnicodeError, ValueError) as error:
                rows[n] = {'left': f'authored reader refusal: {error}', 'bytes': len(raw)}
                continue
            prepared.append((n, raw, a, b, c))
            texts.extend((a, b, c))
        streams = lang_rust.token_streams(*texts) if texts else []
        for k, (n, raw, a, b, c) in enumerate(prepared):
            sa, sb, sc = streams[k*3:k*3+3]
            if sa == ['invalid']:
                rows[n] = {'left': 'authored text refused by rustc lexer (2021)', 'bytes': len(raw)}
                continue
            if ['invalid'] in (sb, sc):
                raise RuntimeError(f'{n}: a projected text is refused by the compiler lexer')
            try:
                assert_tokens(sa, sb, sc)
            except RuntimeError as error:
                raise RuntimeError(f'{n}: {error}') from error
            row = {'sha256_A': sha(raw), 'A': [len(raw), raw.count(b'\n')],
                   'C_docs_kept': doc_reasons.get(owners[n], [])}
            for form, text in [('B', b), ('C', c)]:
                data = text.encode()
                row[form] = [len(data), data.count(b'\n')]
                row['sha256_' + form] = sha(data)
                if data != raw:
                    p = output / form / n
                    metadata = p.stat()
                    p.write_bytes(data)
                    os.utime(p, ns=(metadata.st_atime_ns, metadata.st_mtime_ns))
                    changes[form][n] = (sha(raw), sha(data))
            rows[n] = row
        print(f'checked {min(offset+batch, len(names))}/{len(names)} files', flush=True)
    forms = {}
    for form in ('B', 'C'):
        checksums = checksum_update(output / form, changes[form])
        forms[form] = inventory(output / form)
        forms[form]['cargo_checksums_updated'] = checksums
        atomic_json(output / (form + '-manifest.json'), forms[form])
    if inventory(authored) != baseline:
        raise RuntimeError('authored input changed during preparation')
    atomic_json(output / 'A-manifest.json', baseline)
    result = {'version': VERSION_ID, 'preparer_sha256': sha(Path(__file__).read_bytes()),
              'lean': VERSION, 'renderer': project.IDENTITY,
              'lexer': compiler, 'forms': {f: {k: v for k, v in obj.items() if k != 'files'}
                                         for f, obj in [('A', baseline), *forms.items()]},
              'rs_files': len(names), 'changed': {f: len(v) for f, v in changes.items()},
              'left_reasons': dict(Counter(r['left'] for r in rows.values() if 'left' in r)),
              'C_doc_exceptions': doc_reasons, 'files': rows,
              'build_qualified': False, 'compiler_read_counts': 'pending actual build dep-info'}
    atomic_json(output / 'source-report.json', result)
    print(json.dumps({k: v for k, v in result.items() if k not in ('files', 'C_doc_exceptions', 'left_reasons')}, indent=2))


if __name__ == '__main__':
    os.environ['LC_ALL'] = 'C'
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('authored', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    prepare(args.authored.resolve(), args.output.resolve())
