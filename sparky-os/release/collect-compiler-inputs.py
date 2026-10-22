#!/usr/bin/env python3
"""Intersect real compiler dependency files with the native projection proof.

Reports unique file bytes, not elapsed time, physical disk I/O, cache misses or
repeated header parsing. Generated files whose final hash changed are excluded.
"""
from pathlib import Path
import hashlib
import json
import re
import shutil
import subprocess
import sys


def collect(source, report_path):
    source = source.resolve()
    native = json.loads((source / '.sparky-lc/source.json').read_text())
    assert native.get('qualified')
    seen, evidence, resolved = set(), [], {}

    def record(token, directory):
        token = token.strip().rstrip('\\').strip()
        key = (token, directory)
        if key in resolved:
            if resolved[key] is not None:
                seen.add(resolved[key])
            return
        resolved[key] = None
        if token.startswith('/work/source/'):
            path = source / token[len('/work/source/'):]
        elif token.startswith('/'):
            return
        else:
            path = directory / token
        path = path.resolve()
        # Mozilla's exported include tree contains absolute container symlinks.
        # Resolve those back into this exact retained source, never another tree.
        if str(path).startswith('/work/source/'):
            path = (source / str(path)[len('/work/source/'):]).resolve()
        if path.is_relative_to(source):
            name = path.relative_to(source).as_posix()
            if name in native['files']:
                resolved[key] = name
                seen.add(name)

    for path in source.rglob('*'):
        if path.is_symlink() or not path.is_file():
            continue
        name = path.name
        if name.endswith('.o.d'):
            data = path.read_bytes()
            text = data.decode(errors='replace').replace('\\\n', ' ')
            # Absolute CMake dependency paths are unambiguous inside the build
            # container; don't guess the cwd of arbitrary relative Make rules.
            for token in re.findall(r'/work/source/[^\s\\]+', text):
                record(token, source)
        elif name.endswith('.o.pp') and path.parent.name == '.deps':
            data = path.read_bytes()
            text = data.decode(errors='replace').replace('\\\n', ' ')
            # Mozilla writes compiler dependency rules relative to the object
            # directory containing .deps. Require its expected object target;
            # generated resource .pp files are not compiler observations.
            target, separator, dependencies = text.partition(':')
            if not separator or target.strip() != name.removesuffix('.pp'):
                continue
            for token in dependencies.split():
                if not token.endswith(':'):
                    record(token, path.parent.parent)
        elif name.startswith('.') and name.endswith('.o.cmd') and 'build' in path.relative_to(source).parts:
            data = path.read_bytes()
            text = data.decode(errors='replace')
            for line in text.splitlines():
                match = re.match(r'\s*(?:source_\S+\s*:=\s*)?(\.\./[^\s\\]+)', line)
                if match:
                    record(match[1], source / 'build')
        elif name == '.ninja_deps' and shutil.which('ninja'):
            data = path.read_bytes()
            result = subprocess.run(['ninja', '-C', str(path.parent), '-t', 'deps'], capture_output=True, text=True)
            if result.returncode:
                continue
            for line in result.stdout.splitlines():
                if line.startswith('    ') and line.strip():
                    record(line.strip(), path.parent)
        else:
            continue
        evidence.append({'path': path.relative_to(source).as_posix(),
                         'sha256': hashlib.sha256(data).hexdigest()})
    files, changed = [], []
    for name in sorted(seen):
        row = native['files'][name]
        raw = (source / name).read_bytes()
        if hashlib.sha256(raw).hexdigest() != row['final_sha256']:
            changed.append(name)
            continue
        files.append(dict(path=name, projected=row['status'] == 'projected',
                          authored_bytes=row['bytes_in'], compiler_input_bytes=len(raw),
                          authored_sha256=row['sha_in'], compiler_input_sha256=row['final_sha256']))
    authored = sum(r['authored_bytes'] for r in files)
    consumed = sum(r['compiler_input_bytes'] for r in files)
    report = dict(scope='Unique in-tree C/C++ inputs present in compiler dependency evidence and unchanged since the qualified projection; excludes system headers and unobserved files',
                  performance_claim=False, files=files, dependency_evidence=evidence,
                  changed_after_projection=changed, authored_bytes=authored,
                  compiler_input_bytes=consumed, bytes_removed=authored - consumed)
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    print(f'Compiler dependency evidence: {len(files)} unique matching inputs; '
          f'{authored} -> {consumed} bytes, {len(changed)} changed/generated inputs excluded')
    return report


if __name__ == '__main__':
    collect(Path(sys.argv[1]), Path(sys.argv[2]))
