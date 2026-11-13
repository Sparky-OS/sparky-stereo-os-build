#!/usr/bin/env python3
# Sparky Stereo OS: one Cargo workspace (one resolve, one lock) out of the Craft apps' checkouts, and the Rust dynamic
# libraries the apps share. Generated copies only: upstream's files are never changed.
# Created by Daniel Ramos (Capitain Jack) 2026/11/12
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/13
"""suite-tree.py tree  OUT  SUITE.json  APPSDIR  [APP...]
    Copies each app's checkout APPSDIR/APP to OUT/APP (no .git, no target, no xtask), turns its dependencies on a
    sibling checkout into git dependencies on the revision SUITE.json pins (suite-source.py), expands every
    `workspace = true` in the member manifests from that app's own root manifest, drops dev-dependencies and
    lints, and writes OUT/Cargo.toml (members, the union of the [patch] tables, the release
    profile) and OUT/Cargo.lock (the union of the upstream locks, so cargo keeps upstream's
    versions wherever one resolve allows it). Without APP names, every app of SUITE.json.

suite-tree.py shared OUT METADATA.json TREEDIR BINPKG[,BINPKG...] [BINPKG,...]...
    Reads `cargo metadata` of OUT and, in TREEDIR, one `cargo tree -e normal --target T
    --prefix depth -f '{p}|{f}'` listing per binary package (BINPKG.txt) and one for all of them together (all.txt):
    the listings come from the real feature resolver, the metadata graph does not. Writes the
    umbrella dylib crate OUT/shared (craft-suite-shared): every library crate that two or
    more of the given apps (each a comma list of its binary packages) link, pinned to the
    resolved version and features; then adds it as a dependency of each binary package and
    appends `extern crate craft_suite_shared;` to each binary's main.rs. With PER_APP=1 one more library per app.
    SUITE_ABI_SEED (the output of `rustc -vV`) and, per app, SUITE_APP_SEED_<APP> (the app's source revision) enter
    the libraries' names.
"""
import glob, json, os, re, shutil, subprocess, sys, tomllib
from pathlib import Path


def dumps_value(v):
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, list):
        return '[' + ', '.join(dumps_value(x) for x in v) + ']'
    if isinstance(v, dict):
        return '{ ' + ', '.join(f'{key(k)} = {dumps_value(x)}' for k, x in v.items()) + ' }'
    raise TypeError(type(v))


def key(k):
    return k if re.fullmatch(r'[A-Za-z0-9_-]+', k) else json.dumps(k)


def dumps(doc):
    """A small TOML writer: scalars and arrays inline, tables as headers, arrays of tables as [[x]]."""
    out = []

    def is_tables(v):
        return isinstance(v, list) and v and all(isinstance(x, dict) for x in v)

    def emit(path, t):
        scalars = {k: v for k, v in t.items() if not isinstance(v, dict) and not is_tables(v)}
        if path and (scalars or not t):
            out.append('[' + '.'.join(key(p) for p in path) + ']')
        for k, v in scalars.items():
            out.append(f'{key(k)} = {dumps_value(v)}')
        if scalars or not t:
            out.append('')
        for k, v in t.items():
            if is_tables(v):
                for item in v:
                    out.append('[[' + '.'.join(key(p) for p in path + [k]) + ']]')
                    out.extend(f'{key(kk)} = {dumps_value(vv)}' for kk, vv in item.items())
                    out.append('')
            elif isinstance(v, dict) and k in DEP_TABLES:
                out.append('[' + '.'.join(key(p) for p in path + [k]) + ']')
                out.extend(f'{key(kk)} = {dumps_value(vv)}' for kk, vv in v.items())
                out.append('')
            elif isinstance(v, dict):
                emit(path + [k], v)

    emit([], doc)
    return '\n'.join(out) + '\n'


DEP_TABLES = ('dependencies', 'build-dependencies', 'dev-dependencies')


def expand_dep(name, spec, root_deps, app_root):
    if isinstance(spec, str):
        return spec
    spec = dict(spec)
    if spec.pop('workspace', False):
        base = root_deps[name]
        base = {'version': base} if isinstance(base, str) else dict(base)
        if 'path' in base:
            base['path'] = str((app_root / base['path']).resolve())
        feats = list(dict.fromkeys(list(base.get('features', [])) + list(spec.pop('features', []))))
        if feats:
            base['features'] = feats
        for k, v in spec.items():
            if k == 'default-features' and 'default-features' in base:
                continue
            base[k] = v
        return base
    return spec


def expand_manifest(path, root, app_root):
    doc = tomllib.loads(path.read_text())
    pkg = doc.get('package', {})
    for k, v in list(pkg.items()):
        if isinstance(v, dict) and v.get('workspace'):
            pkg[k] = root['workspace']['package'][k]
    doc.pop('lints', None)
    root_deps = root['workspace'].get('dependencies', {})

    def fix(t):
        t.pop('dev-dependencies', None)
        for sect in ('dependencies', 'build-dependencies'):
            if sect in t:
                t[sect] = {n: expand_dep(n, s, root_deps, app_root) for n, s in t[sect].items()}
    fix(doc)
    for tgt in doc.get('target', {}).values():
        fix(tgt)
    doc['target'] = {k: v for k, v in doc.get('target', {}).items() if v}
    if not doc['target']:
        del doc['target']
    path.write_text(dumps(doc))


def cmd_tree(out, suite, appsdir, names):
    out = Path(out)
    out.mkdir(parents=True, exist_ok=False)
    suite = json.loads(Path(suite).read_text())
    source_tool = str(Path(__file__).resolve().parent / 'suite-source.py')
    members, patches, locks, bins = [], {}, {}, {}
    for name in names or list(suite['apps']):
        app = suite['apps'][name]
        dst = out / name
        shutil.copytree(Path(appsdir) / name, dst, symlinks=True, ignore=shutil.ignore_patterns('.git', 'target', 'xtask'))
        pins = [f'{k}={v}' for k, v in app['libs'].items()]
        for step in ('rewrite', 'lock'):
            subprocess.run([sys.executable, source_tool, step, str(dst), suite['fork'], *pins], check=True,
                           stdout=subprocess.DEVNULL)
        root = tomllib.loads((dst / 'Cargo.toml').read_text())
        wanted = set(app['bins'])
        subs = []
        for pattern in root['workspace'].get('members', []):
            subs += [Path(x) for x in sorted(glob.glob(str(dst / pattern)))]
        for sub in subs:
            man = sub / 'Cargo.toml'
            if not man.exists() or sub.name == 'xtask':
                continue
            if sub.parent.name == 'apps' and sub.name not in wanted:
                shutil.rmtree(sub)
                continue
            if sub.resolve() == dst.resolve():
                continue    # the root package: written below, once the workspace tables are out of its manifest
            expand_manifest(man, root, dst)
            members.append(str(sub.relative_to(out)))
        for reg, tbl in root.get('patch', {}).items():
            for crate, val in tbl.items():
                old = patches.setdefault(reg, {}).setdefault(crate, val)
                if old != val:
                    sys.exit(f'{name}: [patch.{reg}] {crate} differs between apps: {old} / {val}')
        lock = tomllib.loads((dst / 'Cargo.lock').read_text())
        for p in lock['package']:
            if p['name'] == 'xtask':
                continue
            locks.setdefault((p['name'], p['version'], p.get('source', '')), p)
        (dst / 'Cargo.toml').rename(dst / 'Cargo.toml.upstream-root')
        (dst / 'Cargo.lock').rename(dst / 'Cargo.lock.upstream')
        if 'package' in root:
            # an app whose root manifest is also a package (AniCraft): the same manifest without its workspace,
            # patch and profile tables, expanded like any member
            text = (dst / 'Cargo.toml.upstream-root').read_text()
            (dst / 'Cargo.toml').write_text(text)
            expand_manifest(dst / 'Cargo.toml', root, dst)
            doc = tomllib.loads((dst / 'Cargo.toml').read_text())
            for k in ('workspace', 'patch', 'profile'):
                doc.pop(k, None)
            (dst / 'Cargo.toml').write_text(dumps(doc))
            members.append(name)
        bins[name] = sorted(wanted)
    root = ['[workspace]', 'resolver = "3"', 'members = ' + dumps_value(members), '',
            '[profile.release]', 'lto = false', 'codegen-units = 1', 'debug = 0', '']
    # a patch no app's lock uses (upstream lists it under [[patch.unused]]) is left out: with every source replaced by
    # a folder, cargo cannot look an unlocked git patch up ("requires a lock file to be present first")
    used = {n for (n, _v, src) in locks if src.startswith('git+')}
    for reg, tbl in patches.items():
        root.append(f'[patch.{key(reg)}]')
        root += [f'{key(c)} = {dumps_value(v)}' for c, v in tbl.items() if (v.get('package', c) if isinstance(v, dict) else c) in used]
        root.append('')
    patch_at = len(root)
    # One resolve holds one version per semver-compatible range: keep the highest of each range, and
    # leave the edges out so cargo rebuilds them (a locked edge to a dropped version stops the resolve).
    def compat(v):
        a = re.match(r'(\d+)\.(\d+)\.(\d+)', v)
        ma, mi, pa = int(a[1]), int(a[2]), int(a[3])
        return (ma,) if ma else ((0, mi) if mi else (0, 0, pa))

    def order(v):
        a = re.match(r'(\d+)\.(\d+)\.(\d+)(.*)', v)
        return (int(a[1]), int(a[2]), int(a[3]), a[4] == '', a[4])
    best = {}
    for (n, v, s_), p in locks.items():
        k = (n, compat(v), s_)
        if k not in best or order(v) > order(best[k]['version']):
            best[k] = p
    lock = ['version = 4', '']
    for p in sorted(best.values(), key=lambda p: (p['name'], p['version'], p.get('source', ''))):
        lock.append('[[package]]')
        for k in ('name', 'version', 'source', 'checksum'):
            if k in p:
                lock.append(f'{k} = {json.dumps(p[k])}')
        lock.append('')
    locks = best
    (out / 'Cargo.lock').write_text('\n'.join(lock))
    (out / 'Cargo.toml').write_text('\n'.join(root[:patch_at]))
    (out / 'suite-bins.json').write_text(json.dumps(bins, indent=1))
    print(f'{len(members)} members, {len(locks)} locked packages')


def read_tree(path, pk):
    """One `cargo tree --prefix none -f '{p}|{f}'` listing: package id -> feature list (the real feature resolver)."""
    index = {}
    for i, p in pk.items():
        src = p.get('source') or ''
        if src.startswith('git+'):
            where = src[4:].split('#')[0]
        elif src.startswith('registry+'):
            where = ''
        else:
            where = str(Path(p['manifest_path']).parent)
        index[(p['name'], p['version'], where)] = i
    feats, edges, roots, procs, stack = {}, {}, [], set(), []
    for line in Path(path).read_text().splitlines():
        m = re.match(r'^(\d+)(\S+) v(\S+)((?: \([^)]*\))*)\|(.*)$', line.replace(' (*)', ''))
        if not m:
            continue
        depth, where = int(m[1]), ''
        for par in re.findall(r'\(([^)]*)\)', m[4]):
            if par == 'proc-macro':
                where = where
            else:
                where = par.split('#')[0]
        i = index.get((m[2], m[3], where))
        if i is None:
            sys.exit(f'{path}: cannot place {line!r}')
        if '(proc-macro)' in m[4]:
            procs.add(i)
        feats.setdefault(i, set()).update(f for f in m[5].split(',') if f)
        del stack[depth:]
        if stack:
            edges.setdefault(stack[-1], set()).add(i)
        else:
            roots.append(i)
        stack.append(i)
    # what the target links: walk from the programs, never into a procedural macro (it and what it
    # uses run in the compiler, not in the program)
    got, todo = {}, list(roots)
    while todo:
        i = todo.pop()
        if i in got or i in procs:
            continue
        got[i] = feats[i]
        todo.extend(edges.get(i, ()))
    return got


def write_umbrella(d, out, base, man, lib):
    """Writes one generated dylib crate with a versioned SONAME: lib<base>-0.<id>.so, where <id> names the
    compiler (SUITE_ABI_SEED, the output of `rustc -vV`) and every crate, version, source and feature in it."""
    import hashlib
    body = '\n'.join(man[man.index('[dependencies]'):]).replace(str(out), '.')
    seed = os.environ.get('SUITE_ABI_SEED', '') + '\n' + os.environ.get('SUITE_APP_SEED_' + base.split('-')[0].upper(), '')
    abi = hashlib.sha256((seed + '\n' + body).encode()).hexdigest()[:8]
    soname = f'lib{base}-0.{abi}.so'
    man = list(man)
    man.insert(man.index('publish = false') + 1, 'build = "build.rs"')
    (d / 'src').mkdir(parents=True, exist_ok=True)
    (d / 'Cargo.toml').write_text('\n'.join(man) + '\n')
    (d / 'src' / 'lib.rs').write_text('\n'.join(lib) + '\n')
    (d / 'build.rs').write_text('// Generated: the library is installed under this name, so the name is its ABI.\n'
                                f'fn main() {{\n    println!("cargo::rustc-link-arg=-Wl,-soname,{soname}");\n}}\n')
    (d / 'soname.txt').write_text(soname + '\n')
    return soname


def cmd_shared(out, metadata, treedir, apps):
    out = Path(out)
    meta = json.loads(Path(metadata).read_text())
    pk = {p['id']: p for p in meta['packages']}
    byname = {}
    for p in meta['packages']:
        if p['id'] in meta['workspace_members']:
            byname[p['name']] = p['id']
    trees = {b: read_tree(Path(treedir) / f'{b}.txt', pk) for app in apps for b in app.split(',')}
    allf = read_tree(Path(treedir) / 'all.txt', pk)
    nodes = {i: {'features': sorted(f)} for i, f in allf.items()}

    def closure(roots):
        seen = set()
        for r in roots:
            seen |= set(trees[pk[r]['name']])
        return seen

    closures = [closure([byname[b] for b in app.split(',')]) for app in apps]
    count = {}
    for c in closures:
        for i in c:
            count[i] = count.get(i, 0) + 1
    members = set(meta['workspace_members'])
    shared = []
    for i, n in sorted(count.items(), key=lambda kv: (pk[kv[0]]['name'], pk[kv[0]]['version'])):
        if n < 2 or i in members:
            continue
        kinds = {k for t in pk[i]['targets'] for k in t['kind']}
        if 'proc-macro' in kinds or not kinds & {'lib', 'rlib'}:
            continue
        shared.append(i)
    sh = out / 'shared'
    (sh / 'src').mkdir(parents=True, exist_ok=True)
    man = ['[package]', 'name = "craft-suite-shared"', 'version = "0.0.0"', 'edition = "2024"', 'publish = false', '',
           '[lib]', 'crate-type = ["dylib"]', '', '[dependencies]']
    lib = ['//! Generated by suite-tree.py: the crates two or more Craft apps link, as one Rust dynamic library.',
           '#![allow(unused_extern_crates, clippy::all)]']
    for n, i in enumerate(shared):
        p = pk[i]
        spec = {'package': p['name'], 'default-features': False}
        src = p.get('source') or ''
        if src.startswith('git+'):
            m = re.match(r'git\+(.*?)\?(rev|tag|branch)=([^#]*)#', src)
            spec['git'] = m[1]
            spec[m[2]] = m[3]
        elif src.startswith('registry+'):
            spec['version'] = '=' + p['version']
        else:
            spec['path'] = str(Path(p['manifest_path']).parent)
        feats = nodes[i]['features']
        if feats:
            spec['features'] = feats
        man.append(f's{n} = {dumps_value(spec)}')
        lib.append(f'extern crate s{n}; // {p["name"]} {p["version"]}')
    print(write_umbrella(sh, out, 'craft-suite-shared', man, lib))
    root = (out / 'Cargo.toml').read_text()
    if '"shared"' not in root:
        root = root.replace('members = [', 'members = ["shared", ', 1)
    extra = {}
    if os.environ.get('PER_APP') == '1':
        # One more dylib per app: what two or more of that app's own programs link and no other app does.
        for app in apps:
            binpk = app.split(',')
            if len(binpk) < 2:
                continue
            per = {}
            for b in binpk:
                for i in closure([byname[b]]):
                    per[i] = per.get(i, 0) + 1
            own = []
            for i, n in sorted(per.items(), key=lambda kv: (pk[kv[0]]['name'], pk[kv[0]]['version'])):
                kinds = {k for t in pk[i]['targets'] for k in t['kind']}
                if n < 2 or i in shared or 'proc-macro' in kinds or not kinds & {'lib', 'rlib'} or pk[i]['name'] in binpk:
                    continue
                own.append(i)
            name = binpk[0] + '-shared'
            d = out / (name)
            (d / 'src').mkdir(parents=True, exist_ok=True)
            m = ['[package]', f'name = "{name}"', 'version = "0.0.0"', 'edition = "2024"', 'publish = false', '',
                 '[lib]', 'crate-type = ["dylib"]', '', '[dependencies]', f'craft-suite-shared = {{ path = {json.dumps(str(sh))} }}']
            l = ['//! Generated by suite-tree.py: what the programs of one app share and no other app links.',
                 '#![allow(unused_extern_crates, clippy::all)]', 'extern crate craft_suite_shared;']
            for n, i in enumerate(own):
                p = pk[i]
                spec = {'package': p['name'], 'default-features': False}
                src = p.get('source') or ''
                if src.startswith('git+'):
                    g = re.match(r'git\+(.*?)\?(rev|tag|branch)=([^#]*)#', src)
                    spec['git'] = g[1]
                    spec[g[2]] = g[3]
                elif src.startswith('registry+'):
                    spec['version'] = '=' + p['version']
                else:
                    spec['path'] = str(Path(p['manifest_path']).parent)
                if nodes[i]['features']:
                    spec['features'] = nodes[i]['features']
                m.append(f'a{n} = {dumps_value(spec)}')
                l.append(f'extern crate a{n}; // {p["name"]} {p["version"]}')
            print(write_umbrella(d, out, name, m, l))
            (d / 'crates.txt').write_text(''.join(f'{pk[i]["name"]} {pk[i]["version"]}\n' for i in own))
            if json.dumps(name) not in root:
                root = root.replace('members = [', f'members = [{json.dumps(name)}, ', 1)
            for b in binpk:
                extra[b] = (name, d)
            print(f'{len(own)} crates in {name}')
    (out / 'Cargo.toml').write_text(root)
    for app in apps:
        for b in app.split(','):
            mdir = Path(pk[byname[b]]['manifest_path']).parent
            man_path = mdir / 'Cargo.toml'
            text = man_path.read_text()
            wanted = [('craft-suite-shared', sh)] + ([extra[b]] if b in extra else [])
            for dep, dpath in wanted:
                if f'\n{dep} = ' not in text:
                    text = text.replace('[dependencies]\n', f'[dependencies]\n{dep} = {{ path = {json.dumps(str(dpath))} }}\n', 1)
            man_path.write_text(text)
            for t in pk[byname[b]]['targets']:
                if 'bin' in t['kind']:
                    src = Path(t['src_path'])
                    s = src.read_text()
                    for dep, _ in wanted:
                        line = f'extern crate {dep.replace("-", "_")};'
                        if line not in s:
                            s = s.rstrip('\n') + '\n\n' + line + '\n'
                    src.write_text(s)
    (out / 'shared' / 'crates.txt').write_text(''.join(f'{pk[i]["name"]} {pk[i]["version"]}\n' for i in shared))
    print(f'{len(shared)} crates in craft-suite-shared; closures: {[len(c) for c in closures]}')


if __name__ == '__main__':
    if len(sys.argv) >= 5 and sys.argv[1] == 'tree':
        cmd_tree(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5:])
    elif len(sys.argv) >= 6 and sys.argv[1] == 'shared':
        cmd_shared(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5:])
    else:
        sys.exit(__doc__)
