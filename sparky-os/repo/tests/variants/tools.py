#!/usr/bin/python3 -B
# The round's other tools on a tree with an amd64v3 index (ORDER 108), each against the script from before the change (OLD, main's
# sparky-os subset) and the one under test (NEW). Usage: tools.py NEW_SPARKY_OS OLD_SPARKY_OS TREE WORK
# TREE is the throwaway tree the real publish-tree.sh made with a variant build; NEW and OLD hold repo/, release/, lean/, config/, apt/.
import hashlib, importlib.util, json, os, subprocess, sys
from pathlib import Path

new, old, tree, work = (Path(a) for a in sys.argv[1:5])
failed = 0


def check(ok, text):
    global failed
    print(('PASS ' if ok else 'FAIL ') + text)
    failed |= not ok


def load(root, rel, name):
    for p in (str(root), str(root / 'release'), str(root / 'config')):
        if p not in sys.path:
            sys.path.insert(0, p)
    spec = importlib.util.spec_from_file_location(name, root / rel)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


# 1. check-installable.py: the indexes it reads (both modes). Red: the old one reads binary-amd64v3 as an architecture of its own.
for label, root in (('old', old), ('new', new)):
    ci = load(root, 'repo/check-installable.py', 'ci_' + label)
    (work / ('ci-' + label)).mkdir(parents=True, exist_ok=True)
    for unsigned in (True, False):
        fields, indexes, trust = ci.tree_release(tree, 'mashtabba', unsigned, work / ('ci-' + label))
        names = sorted(p.parent.name for p in indexes)
        mode = 'unsigned' if unsigned else 'signed'
        if label == 'old':
            check('binary-amd64v3' in names, f'red: the script from before reads {names} of the variant tree ({mode})')
        else:
            check('binary-amd64v3' not in names and 'binary-amd64' in names, f'green: the new one reads {names} ({mode})')

# 2. supply_chain.read_packages_index: keyed by Filename, so both builds are listed once each
sc = load(new, 'release/supply_chain.py', 'supply_chain')
index = sc.read_packages_index(tree)
files = sorted(Path(f).name for f in index)
check(any(f.endswith('_amd64v3.deb') for f in files) and any(f == 'a_1.0_amd64.deb' for f in files) and len(files) == len(set(files)),
      f'supply_chain.read_packages_index lists the baseline and the variant build, each once: {files}')

# 3. verify-online-repository.py's Release loop, offline: every row's file and its by-hash copy exist and match
dists = tree / 'dists/mashtabba'
rows = [r.split() for r in (dists / 'Release').read_text().split('SHA256:')[1].splitlines() if r.strip()]
bad = []
for expected, size, rel in rows:
    path = dists / rel
    ok = path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() == expected and path.stat().st_size == int(size)
    byhash = path.parent / 'by-hash/SHA256' / expected
    if not (ok and byhash.is_file()):
        bad.append(rel)
check(not bad and any('binary-amd64v3' in r[2] for r in rows),
      f'every Release row of the variant tree, binary-amd64v3 included, has its file and its by-hash copy ({len(rows)} rows); verify-online-repository.py reads Release by rows and needs no change')

# 4. make-sbom.py: the purl of a variant differs from its baseline twin's
for label, root in (('old', old), ('new', new)):
    out = work / f'sbom-{label}.json'
    r = subprocess.run([sys.executable, '-B', str(root / 'release/make-sbom.py'), '--tree', str(tree), '--name', 'toy', '--out', str(out)],
                       capture_output=True, text=True, env=dict(os.environ, SPARKY_STEREO_CONFIG='/nonexistent'))
    if r.returncode != 0:
        check(False, f'make-sbom.py ({label}) failed: {r.stderr.strip().splitlines()[-1:]}')
        continue
    doc = json.loads(out.read_text())
    purls = [x['externalRefs'][0]['referenceLocator'] for x in doc['packages'] if x.get('name') == 'a' and x.get('externalRefs')
             and x['externalRefs'][0]['referenceLocator'].startswith('pkg:deb/') and 'arch=source' not in x['externalRefs'][0]['referenceLocator']]
    if label == 'old':
        check(len(purls) == 2 and len(set(purls)) == 1, f'red: the old SBOM gives the two builds of a one purl: {purls}')
    else:
        check(len(purls) == 2 and len(set(purls)) == 2, f'green: the new SBOM gives them two: {purls}')
sys.exit(failed)
