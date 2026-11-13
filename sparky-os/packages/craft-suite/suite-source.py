#!/usr/bin/env python3
# Sparky Stereo OS: the offline source of the Craft suite: path dependencies on a sibling checkout become pinned git
# dependencies, and every crate is vendored in a folder of its own source (the registry, or one git revision).
# Created by Daniel Ramos (Capitain Jack) 2026/11/13
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/13
"""suite-source.py rewrite APPDIR FORK NAME=REV [NAME=REV...]
    In every Cargo.toml under APPDIR, a dependency on a sibling checkout (path = "../NAME/crates/X") becomes
    git = "FORK/<repository>", rev = "REV": the repository is NAME up to its first suffix (craft-libs-depth is a
    worktree of craft-libs). A sibling path no NAME covers stops the run. Prints the lines it changed.

suite-source.py lock APPDIR FORK NAME=REV [NAME=REV...]
    Gives the packages of APPDIR/Cargo.lock that came from such a sibling checkout (no source, and not a member of
    the app's own workspace) their git source, so the lock names what the manifests now name.

suite-source.py merge OUT APP=VENDORDIR=CARGO.LOCK [...]
    Merges the folders `cargo vendor --versioned-dirs` wrote for each app into OUT/registry and
    OUT/git/<repository>-<revision>/, one folder per source: one vendor folder cannot hold two git revisions of a
    crate at one version. The same crate from the same source must be the same bytes in every app.

suite-source.py config OUT BASE
    Prints the cargo configuration that replaces every source with its folder under BASE (the path OUT has at
    build time)."""
import hashlib
import json
import re
import shutil
import sys
import tomllib
from pathlib import Path

SIBLING = re.compile(r'path\s*=\s*"(?:\.\./)+([A-Za-z0-9_-]+)/crates/[^"]+"')
GIT = re.compile(r'git\+(?P<url>[^?#]+)\?rev=(?P<rev>[0-9a-f]{40})#(?P=rev)$')


def repository(name):
    for known in ('craft-libs',):
        if name == known or name.startswith(known + '-'):
            return known
    return name


def pins(args):
    return dict(a.split('=', 1) for a in args)


def manifests(app):
    for path in sorted(app.rglob('Cargo.toml')):
        if not {'target', '.git'} & set(path.relative_to(app).parts):
            yield path


def cmd_rewrite(app, fork, revs):
    app = Path(app)
    for path in manifests(app):
        text = path.read_text()

        def swap(m):
            name = m[1]
            if name not in revs:
                sys.exit(f'{path}: a dependency on the sibling checkout ../{name} has no pinned revision')
            return f'git = "{fork}/{repository(name)}", rev = "{revs[name]}"'
        new = SIBLING.sub(swap, text)
        if new != text:
            path.write_text(new)
            for a, b in zip(text.splitlines(), new.splitlines()):
                if a != b:
                    print(f'{path.relative_to(app)}: {b.strip()}')


def cmd_lock(app, fork, revs):
    app = Path(app)
    if len(set(revs.values())) != 1 or len({repository(n) for n in revs}) != 1:
        sys.exit('an app takes its sibling crates from one revision of one repository')
    name, rev = next(iter(revs.items()))
    source = f'git+{fork}/{repository(name)}?rev={rev}#{rev}'
    members = set()
    for path in manifests(app):
        doc = tomllib.loads(path.read_text())
        if 'package' in doc:
            members.add(doc['package']['name'])
    out, block, changed = [], [], 0

    def flush():
        nonlocal changed
        if block and block[0] == '[[package]]':
            keys = {line.split(' = ', 1)[0]: line for line in block[1:] if ' = ' in line and not line.startswith(' ')}
            pkg = json.loads(keys['name'].split(' = ', 1)[1])
            if 'source' not in keys and pkg not in members:
                at = next(i for i, line in enumerate(block) if line.startswith('version = '))
                block.insert(at + 1, f'source = {json.dumps(source)}')
                changed += 1
        out.extend(block)
        block.clear()
    for line in (app / 'Cargo.lock').read_text().splitlines():
        if line == '[[package]]':
            flush()
        block.append(line)
    flush()
    (app / 'Cargo.lock').write_text('\n'.join(out) + '\n')
    print(f'{changed} locked packages now come from {source}')


def tree_digest(folder):
    h = hashlib.sha256()
    for path in sorted(p for p in folder.rglob('*') if p.is_file() or p.is_symlink()):
        h.update(path.relative_to(folder).as_posix().encode() + b'\0')
        h.update(str(path.readlink()).encode() if path.is_symlink() else hashlib.sha256(path.read_bytes()).digest())
    return h.hexdigest()


def cmd_merge(out, specs):
    out = Path(out)
    seen, count = {}, {}
    for spec in specs:
        app, vendor, lock = spec.split('=', 2)
        sources = {}
        # the lock, not `cargo metadata`: the metadata leaves out optional dependencies no default feature turns on,
        # and cargo vendor copies every locked package
        for p in tomllib.loads(Path(lock).read_text())['package']:
            if 'source' not in p:
                continue
            key = (p['name'], p['version'])
            if key in sources and sources[key] != p['source']:
                sys.exit(f'{app}: {p["name"]} {p["version"]} comes from two sources: {sources[key]} and {p["source"]}')
            sources[key] = p['source']
        for folder in sorted(Path(vendor).iterdir()):
            if not (folder / 'Cargo.toml').exists():
                continue
            pkg = tomllib.loads((folder / 'Cargo.toml').read_text())['package']
            key = (pkg['name'], pkg['version'])
            if key not in sources:
                sys.exit(f'{app}: vendored crate {folder.name} is in no source of the app')
            source = sources[key]
            if source.startswith('registry+'):
                where = out / 'registry'
            else:
                m = GIT.match(source)
                if not m:
                    sys.exit(f'{app}: {folder.name}: source {source} is not a registry or a git revision')
                where = out / 'git' / (m['url'].rstrip('/').removesuffix('.git').rsplit('/', 1)[1] + '-' + m['rev'][:8])
                seen.setdefault(where, source)
                if seen[where] != source:
                    sys.exit(f'{where.name} would hold two sources: {seen[where]} and {source}')
            dest = where / folder.name
            if dest.exists():
                if tree_digest(dest) != tree_digest(folder):
                    sys.exit(f'{app}: {folder.name} from {source} differs from the copy another app vendored')
                continue
            where.mkdir(parents=True, exist_ok=True)
            shutil.copytree(folder, dest, symlinks=True)
            count[where.name] = count.get(where.name, 0) + 1
    (out / 'sources.json').write_text(json.dumps({str(w.relative_to(out)): s for w, s in sorted(seen.items())}, indent=1) + '\n')
    for name, n in sorted(count.items()):
        print(f'{n:5d} crates in {name}')


def cmd_config(out, base):
    out = Path(out)
    lines = ['[source.crates-io]', 'replace-with = "suite-registry"', '', '[source.suite-registry]',
             f'directory = {json.dumps(base + "/registry")}', '']
    for where, source in sorted(json.loads((out / 'sources.json').read_text()).items()):
        m = GIT.match(source)
        name = 'suite-' + where.replace('/', '-')
        lines += [f'[source.{json.dumps(source.split("#")[0])}]', f'git = {json.dumps(m["url"])}', f'rev = {json.dumps(m["rev"])}',
                  f'replace-with = {json.dumps(name)}', '', f'[source.{name}]', f'directory = {json.dumps(base + "/" + where)}', '']
    print('\n'.join(lines))


if __name__ == '__main__':
    a = sys.argv[1:]
    if len(a) >= 4 and a[0] == 'rewrite':
        cmd_rewrite(a[1], a[2], pins(a[3:]))
    elif len(a) >= 4 and a[0] == 'lock':
        cmd_lock(a[1], a[2], pins(a[3:]))
    elif len(a) >= 3 and a[0] == 'merge':
        cmd_merge(a[1], a[2:])
    elif len(a) == 3 and a[0] == 'config':
        cmd_config(a[1], a[2])
    else:
        sys.exit(__doc__)
