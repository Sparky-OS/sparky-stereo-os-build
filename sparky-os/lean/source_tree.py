# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""Source projection for disposable builds, with exact authored recovery.

C/C++ is the default. A retained language plan explicitly opts a Java, Zig or Rust build in;
its JDK, zig or rustc must be installed before this stage, as for the actual compiler.
"""
import argparse
from dataclasses import asdict
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import re

from . import VERSION, lang_c, lang_rust, lang_zig, project

EXCLUDED = {'.git', '.pc', 'debian', '.sparky-lc', 'build'}
PRESERVE_PLAN = 'debian/sparky-lean-preserve.json'
LANGUAGE_PLAN = 'debian/sparky-lean-languages.json'
PAYLOAD_SOURCE_PLAN = 'debian/sparky-lean-payload-sources.json'
# installed files a build step generates in a declared form from a source copy (Zig's install step writes every
# *test.zig as an empty placeholder): pattern -> {"form": "empty" or "sha256:HEX", "reason": why}
PAYLOAD_GENERATED_PLAN = 'debian/sparky-lean-payload-generated.json'
EXTENSIONS = {'c': lang_c.EXTS | lang_c.ASM_EXTS, 'java': {'.java'}, 'zig': lang_zig.EXTS, 'rust': lang_rust.EXTS}
# procedural-macro crates that read their callers' source text, each with the review that decided what stays authored
# for it: {"crate folder": "what was reviewed"}; without an entry the projection stops and names the crate
RUST_READERS_PLAN = 'debian/sparky-lean-rust-readers.json'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def preservation_plan(root):
    path = root / PRESERVE_PLAN
    if not path.exists():
        return {}
    plan = json.loads(path.read_text())
    if not isinstance(plan, dict):
        raise ValueError('Source preservation plan must map relative patterns to reasons')
    for pattern, reason in plan.items():
        if (not isinstance(pattern, str) or not pattern or pattern.startswith('/')
                or '..' in pattern.split('/') or '\\' in pattern
                or not isinstance(reason, str) or not reason.strip()):
            raise ValueError('Source preservation needs a safe relative pattern and a reason')
    return plan


def project_tree(root):
    evidence = root / '.sparky-lc'
    report = evidence / 'source.json'
    plan = preservation_plan(root)
    language_path = root / LANGUAGE_PLAN
    languages = json.loads(language_path.read_text()) if language_path.exists() else ['c']
    if (not isinstance(languages, list) or not languages
            or any(not isinstance(name, str) or name not in EXTENSIONS for name in languages)
            or len(languages) != len(set(languages))):
        raise ValueError('Source language plan must name supported, unique languages: ' + ', '.join(sorted(EXTENSIONS)))
    languages = sorted(languages)
    extensions = set().union(*(EXTENSIONS[name] for name in languages))
    if report.exists():
        obj = json.loads(report.read_text())
        if obj['engine'] != VERSION or not obj.get('qualified'):
            raise ValueError('Engine changed or incomplete projection; restore and start a fresh build')
        if obj.get('preserve', {}) != plan:
            raise ValueError('Source preservation plan changed; restore and start a fresh build')
        if obj.get('languages', ['c']) != languages:
            raise ValueError('Source language plan changed; restore and start a fresh build')
        for name, row in obj['files'].items():
            if sha((root / name).read_bytes()) != row['final_sha256']:
                raise ValueError(f'Source changed after projection: {name}')
        return
    paths = []
    for path in sorted(root.rglob('*')):
        rel = path.relative_to(root)
        suffix = path.suffix if path.suffix in lang_c.ASM_EXTS else path.suffix.lower()   # `.s` is no cpp input
        if (path.is_symlink() or not path.is_file() or suffix not in extensions
                or any(p in EXCLUDED or p.startswith('obj-') for p in rel.parts)):
            continue
        paths.append(path)
    names = [p.relative_to(root).as_posix() for p in paths]
    for pattern in plan:
        if not any(fnmatch.fnmatchcase(name, pattern) for name in names):
            raise ValueError(f'Source preservation pattern matches no eligible file: {pattern}')
    evidence.mkdir(exist_ok=True)
    records = {}
    # a file another source file reads as data (Zig's @embedFile) is that file's input, not code to project
    readers = project.read_as_data({'/' + n: p.read_bytes() for p, n in zip(paths, names) if project.reads_others(n)},
                                   ('/' + n for n in names))
    rust_left = rust_readers(root, names) if 'rust' in languages else {}
    if 'rust' in languages:
        prime_rust(paths, names, plan, readers, rust_left)
    position_lines = {}
    for path, name in zip(paths, names):
        rel = path.relative_to(root)
        raw = path.read_bytes()
        metadata = path.stat()
        reasons = [reason for pattern, reason in plan.items()
                   if fnmatch.fnmatchcase(name, pattern)]
        if '/' + name in readers:
            reasons.append(readers['/' + name])
        if name in rust_left:
            reasons.append(rust_left[name])
        if reasons:
            result = project.Result(path='/' + name, status='left',
                                    reason='additional source consumer: ' + '; '.join(reasons),
                                    bytes_in=len(raw), bytes_out=len(raw), sha_in=sha(raw))
        else:
            result = project.project('/' + name, raw, package='native-build', pointer=False, native=True)
        row = asdict(result)
        row.pop('lean')
        row['final_sha256'] = sha(result.lean if result.lean is not None else raw)
        row['source_mtime_ns'] = metadata.st_mtime_ns
        records[rel.as_posix()] = row
        if result.status == 'projected' and result.handler == 'rust':
            where = lang_rust.lines(raw.decode('utf-8'))
            if where:
                position_lines[name] = where
        if result.status == 'projected':
            original = evidence / 'authored' / rel
            original.parent.mkdir(parents=True, exist_ok=True)
            original.write_bytes(raw)
            path.write_bytes(result.lean)
            os.utime(path, ns=(metadata.st_atime_ns, metadata.st_mtime_ns))
        if result.reason.startswith(('check failed:', 'the c reader', 'the java reader', 'the zig reader', 'the rust reader',
                                     'not stable')):
            # Retain recovery records even when qualification fails.
            report.write_text(json.dumps({'engine': VERSION, 'files': records}, indent=2) + '\n')
            raise ValueError(f'{rel}: {result.reason}')
    report.write_text(json.dumps({'engine': VERSION, 'qualified': True,
                                 'preserve': plan, 'languages': languages,
                                 'options': 'collapse-blank,no-pointer,C/C++ line breaks kept',
                                 'renderer': project.IDENTITY,
                                 # Rust files whose own code reads its position: these values name lean lines
                                 'position_lines': position_lines,
                                 'stage': 'before compilation', 'files': records}, indent=2) + '\n')
    print(f'Build-input Lean Code: {sum(r["status"] == "projected" for r in records.values())}/{len(records)} files projected')


def _manifest_folders(root, names):
    folders = set()
    for name in names:
        parts = name.split('/')[:-1]
        for depth in range(len(parts), -1, -1):
            folder = '/'.join(parts[:depth])
            if folder in folders:
                break
            if (root / folder / 'Cargo.toml').is_file():
                folders.add(folder)
                break
    return folders


def rust_readers(root, names):
    """{file: reason} for the Rust files that stay authored because something reads Rust source text that no
    compiler check sees. A crate whose build script reads source text stays authored whole. A procedural-macro
    crate that asks spans for their source text reads its callers' files, which this step cannot list: the
    projection stops and names the crate until debian/sparky-lean-rust-readers.json records its review."""
    rust = [n for n in names if n.endswith('.rs')]
    folders = sorted(_manifest_folders(root, rust), key=len, reverse=True)

    def crate_of(name):
        return next((f for f in folders if f == '' or name.startswith(f + '/')), None)
    members = {}
    for name in rust:
        members.setdefault(crate_of(name), []).append(name)
    reviewed_path = root / RUST_READERS_PLAN
    reviewed = json.loads(reviewed_path.read_text()) if reviewed_path.exists() else {}
    if not isinstance(reviewed, dict) or any(not isinstance(k, str) or not isinstance(v, str) or not v.strip()
                                             for k, v in reviewed.items()):
        raise ValueError('The Rust source-reader plan must map crate folders to the review that decided them')
    left, unreviewed = {}, []
    for folder, files in sorted(members.items(), key=lambda kv: kv[0] or ''):
        if folder is None:
            continue
        manifest = (root / folder / 'Cargo.toml').read_text(errors='replace')
        script = re.search(r'^build\s*=\s*"([^"]+)"', manifest, re.M)
        script = (folder + '/' if folder else '') + (script.group(1) if script else 'build.rs')
        if (root / script).is_file():
            why = lang_rust.source_reader(script, (root / script).read_text(errors='replace'))
            if why:
                for name in files:
                    left[name] = 'its crate\'s build script reads Rust source text: ' + why
                continue
        if re.search(r'^proc[-_]macro\s*=\s*true', manifest, re.M):
            for name in files:
                why = lang_rust.source_reader(name, (root / name).read_text(errors='replace'), macro=True)
                if why and folder not in reviewed:
                    unreviewed.append(f'{folder or "."}: {why}')
                    break
    if unreviewed:
        raise ValueError('Procedural macros that read their callers\' source text, not reviewed in '
                         + RUST_READERS_PLAN + ' (a macro that reads comments is a consumer no compiler check sees): '
                         + '; '.join(unreviewed))
    return left


def prime_rust(paths, names, plan, readers, rust_left):
    """One rustc start per few hundred files instead of two per file: the authored texts and their renders are
    read ahead; project() then finds each file's token digest remembered."""
    texts = []
    for path, name in zip(paths, names):
        if (not name.endswith('.rs') or '/' + name in readers or name in rust_left
                or any(fnmatch.fnmatchcase(name, pattern) for pattern in plan)):
            continue
        try:
            text = path.read_bytes().decode('utf-8')
        except UnicodeDecodeError:
            continue
        if '\r' in text or lang_rust.refuse(text):
            continue
        texts.append(text)
        try:
            lean, rendered, _ = project.render_text(text, 'rust', None, None, None, pointer=False)
        except Exception:      # project() names it for this file
            continue
        if rendered.removed:
            texts.append(lean)
    if texts and lang_rust.rustc():
        lang_rust.prime(texts)


def authored(root):
    evidence = root / '.sparky-lc'
    report = evidence / 'source.json'
    if not report.exists():
        return []
    out = []
    for name, row in json.loads(report.read_text())['files'].items():
        if row['status'] != 'projected':
            continue
        raw = (evidence / 'authored' / name).read_bytes()
        if sha(raw) != row['sha_in']:
            raise ValueError(f'Authored recovery copy changed: {name}')
        out.append((name, row, raw))
    return out


def restore_tree(root):
    for name, row, raw in authored(root):
        path = root / name
        if sha(path.read_bytes()) not in (row['final_sha256'], row['sha_in']):
            raise ValueError(f'Refusing to overwrite modified source: {name}')
        path.write_bytes(raw)
        os.utime(path, ns=(path.stat().st_atime_ns, row['source_mtime_ns']))


def form_digest(form):
    """The SHA-256 a declared generated output must have: "empty", or "sha256:HEX" for any other exact content."""
    if form == 'empty':
        return sha(b'')
    match = re.fullmatch(r'sha256:([0-9a-f]{64})', form or '')
    if not match:
        raise ValueError(f'Unknown generated-output form {form!r}: use "empty" or "sha256:HEX"')
    return match.group(1)


def check_generated(plan):
    """A generated-output plan as debian_prepare writes it: {absolute installed pattern: {"form", "reason"}}."""
    if not isinstance(plan, dict):
        raise ValueError('Generated-output plan must map installed patterns to their form and reason')
    out = {}
    for pattern, row in plan.items():
        if (not isinstance(pattern, str) or not pattern.startswith('/') or '\\' in pattern
                or '..' in Path(pattern).parts or not isinstance(row, dict)
                or not isinstance(row.get('reason'), str) or not row['reason'].strip()):
            raise ValueError('A generated output needs an absolute installed pattern, its form and a reason')
        out[pattern] = {'form': row.get('form'), 'reason': row['reason'], 'sha256': form_digest(row.get('form'))}
    return out


def generated_plan(root):
    path = root / PAYLOAD_GENERATED_PLAN
    return check_generated(json.loads(path.read_text())) if path.exists() else {}


def installed_files(staging):
    for path in staging.rglob('*'):
        if path.is_symlink() or not path.is_file() or 'DEBIAN' in path.relative_to(staging).parts:
            continue
        yield path, '/' + path.relative_to(staging).as_posix()


def require_generated(root, stagings):
    """Every declared generated output matches at least one installed file of the build's packages, or the build
    stops: a declaration that matches nothing explains nothing."""
    plan = generated_plan(root)
    if not plan:
        return
    paths = [installed for staging in stagings for _, installed in installed_files(staging)]
    for pattern in plan:
        if not any(fnmatch.fnmatchcase(installed, pattern) for installed in paths):
            raise ValueError(f'Declared generated output matches no installed file: {pattern}')


def restore_payload(root, staging, check_coverage=True):
    """After installation, restore copied headers before the distinct payload projection.

    Do not restore the compilation tree before dh_auto_install: older debhelper
    invokes make/ninja install and may rebuild it. Refuse ambiguous HR mappings.
    An installed file matching a declared generated output (debian/sparky-lean-payload-generated.json) must be
    exactly its declared form; it is left as it is and recorded as generated. Any other change is refused.
    check_coverage=False: the caller checks every declared pattern over all its packages (require_generated).
    """
    by_hash = {}
    by_name = {}
    for name, row, raw in authored(root):
        by_hash.setdefault(row['final_sha256'], []).append((name, raw))
        by_name[name] = raw
    mappings = {}
    plan = root / PAYLOAD_SOURCE_PLAN
    if plan.exists():
        mappings = json.loads(plan.read_text())
        if not isinstance(mappings, dict):
            raise ValueError('Payload source plan must map installed prefixes to source directories')
        for prefix, directory in mappings.items():
            if (not isinstance(prefix, str) or not prefix.startswith('/') or '\\' in prefix
                    or '..' in Path(prefix).parts or Path(prefix).as_posix() != prefix
                    or not isinstance(directory, str) or not directory or directory.startswith('/')
                    or '..' in Path(directory).parts or '\\' in directory):
                raise ValueError('Unsafe payload source mapping')
    source_report = root / '.sparky-lc/source.json'
    records = json.loads(source_report.read_text())['files'] if mappings else {}
    ordered = sorted(mappings, key=len, reverse=True)
    generated = generated_plan(root)
    if check_coverage:
        require_generated(root, [staging])
    restored = 0
    made = {}
    for path, installed in installed_files(staging):
        digest = sha(path.read_bytes())
        pattern = next((p for p in generated if fnmatch.fnmatchcase(installed, p)), None)
        if pattern is not None:
            if digest != generated[pattern]['sha256']:
                raise ValueError(f'Declared generated output is not its declared form ({generated[pattern]["form"]}): '
                                 f'{path}')
            made[installed] = {'pattern': pattern, 'form': generated[pattern]['form'],
                               'reason': generated[pattern]['reason'], 'sha256': digest}
            continue
        prefix = next((p for p in ordered if installed.startswith(p.rstrip('/') + '/')), None)
        if prefix is not None:
            relative = installed[len(prefix.rstrip('/')) + 1:]
            name = (Path(mappings[prefix]) / relative).as_posix()
            row = records.get(name)
            if row is not None:
                if digest == row['sha_in']:
                    continue  # includes genuine empty headers, never projected
                if digest != row['final_sha256'] or name not in by_name:
                    raise ValueError(f'Mapped source copy changed during staging: {path}')
                path.write_bytes(by_name[name])
                restored += 1
            # Unknown paths under an explicit copy layout are generated files;
            # do not infer their origin from a coincidental content hash.
            continue
        candidates = by_hash.get(digest, [])
        if not candidates:
            continue
        named = [(n, raw) for n, raw in candidates if Path(n).name == path.name]
        choices = {raw for _, raw in named or candidates}
        if len(choices) != 1:
            raise ValueError(f'Ambiguous authored mapping for installed file: {path}')
        path.write_bytes(choices.pop())
        restored += 1
    if made:
        record = root / '.sparky-lc/payload-generated.json'
        known = json.loads(record.read_text()) if record.exists() else {}
        known.update(made)
        record.parent.mkdir(exist_ok=True)
        record.write_text(json.dumps(known, indent=2, sort_keys=True) + '\n')
        print(f'{len(made)} installed files are declared generated outputs, each in its declared form: '
              + '; '.join(sorted({f"{r['pattern']} ({r['form']}): {r['reason']}" for r in made.values()})))
    print(f'Restored {restored} installed source files before payload projection')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('project', 'restore', 'restore-payload'))
    parser.add_argument('root', type=Path)
    parser.add_argument('staging', type=Path, nargs='?')
    args = parser.parse_args()
    try:
        if args.action == 'project':
            project_tree(args.root.resolve())
        elif args.action == 'restore':
            restore_tree(args.root.resolve())
        elif args.staging is None:
            parser.error('restore-payload requires STAGING')
        else:
            restore_payload(args.root.resolve(), args.staging.resolve())
    except (ValueError, OSError) as error:
        parser.exit(1, str(error) + '\n')
