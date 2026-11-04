#!/bin/bash
# Red and green test of the bill of materials and provenance tools (ORDER 394).
# Run in a container that has dpkg-dev and the tools' Python venv: PY=/opt/v/bin/python bash test.sh WORKDIR
set -euo pipefail
PY=${PY:-/opt/v/bin/python}
W=${1:?work directory}
R=$(cd "$(dirname "$0")/../../release" && pwd)
T=$(cd "$(dirname "$0")" && pwd)
rm -rf "$W"; mkdir -p "$W"
fail=0
expect() {  # expect green|red LABEL COMMAND...
    local want=$1 label=$2; shift 2
    if "$@" > "$W/last.out" 2>&1; then got=green; else got=red; fi
    if [ "$got" = "$want" ]; then echo "ok   $want  $label"; else echo "FAIL want $want, got $got: $label"; sed 's/^/     /' "$W/last.out" | head -12; fail=1; fi
}
$PY "$T/make-fixture.py" "$W/tree" > /dev/null
mkdir -p "$W/recipes/fixsrc" "$W/empty" "$W/cohort"
printf 'fixsrc (1.0-1+stereo3d1+lc1) unstable; urgency=low\n' > "$W/recipes/fixsrc/changelog-1.txt"
# a cohort: beta 2.1 replaces the published beta 2.0
mkdir -p "$W/c/beta" "$W/c/beta/DEBIAN"
printf 'Package: beta\nVersion: 2.1\nArchitecture: amd64\nMaintainer: x\nDescription: beta\n' > "$W/c/beta/DEBIAN/control"
mkdir -p "$W/c/beta/usr/share/doc/beta"; cp "$W/tree/pool/main/f/fixture/beta_2.0_amd64.deb" /dev/null
printf 'Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/\n\nFiles: *\nCopyright: 2026 X\nLicense: MIT\n' > "$W/c/beta/usr/share/doc/beta/copyright"
dpkg-deb -Zxz --root-owner-group --build "$W/c/beta" "$W/cohort/beta_2.1_amd64.deb" > /dev/null
echo "$W/cohort/beta_2.1_amd64.deb" > "$W/cohort.list"; (cd /; sha256sum "$W/cohort/beta_2.1_amd64.deb") > "$W/cohort.sha256"
# a .buildinfo for the alpha build
D=$W/tree/pool/main/f/fixture
A=$(sha256sum "$D/alpha_1.0-1+stereo3d1+lc1_amd64.deb" | cut -d' ' -f1)
mkdir -p "$W/bi"
cat > "$W/bi/fixsrc.buildinfo" <<B
Format: 1.0
Source: fixsrc
Architecture: amd64
Version: 1.0-1+stereo3d1+lc1
Checksums-Sha256:
 $A 100 alpha_1.0-1+stereo3d1+lc1_amd64.deb
Build-Origin: Debian
Build-Architecture: amd64
Build-Date: Wed, 04 Nov 2026 02:27:17 +0000
Installed-Build-Depends:
 base-files (= 14.2),
 libc6:amd64 (= 2.42-1)
Environment:
 DEB_BUILD_OPTIONS="parallel=4"
B

expect green "make-sbom on the tree"       $PY "$R/make-sbom.py" --tree "$W/tree" --name fixture --out "$W/sbom.json" --created 2026-11-04T00:00:00Z --report "$W/sbom.report.json"
expect green "check sbom (SPDX validator + tree)" $PY "$R/check-supply-chain.py" sbom "$W/sbom.json" --tree "$W/tree"
expect green "make-sbom with a cohort"     $PY "$R/make-sbom.py" --tree "$W/tree" --cohort-list "$W/cohort.list" --cohort-sha256 "$W/cohort.sha256" --name fixture-next --out "$W/sbom-next.json" --created 2026-11-04T00:00:00Z
expect green "check cohort sbom (no tree)" $PY "$R/check-supply-chain.py" sbom "$W/sbom-next.json"
expect green "make-provenance"             $PY "$R/make-provenance.py" --tree "$W/tree" --buildinfo-dir "$W/bi" --recipes-dir "$W/recipes" --recipes-dir "$W/empty" --out-dir "$W/prov" --report "$W/prov.report.json"
expect green "check provenance (in-toto + SLSA + tree)" $PY "$R/check-supply-chain.py" provenance "$W/prov" --tree "$W/tree"

# the facts the documents must carry (analytic expectations, not the tool's own output)
expect green "licence of alpha is the DEP-5 reading" $PY -I - "$W/sbom.json" <<'P'
import json, sys
d = json.load(open(sys.argv[1]))
p = {x['name']: x for x in d['packages']}
assert p['alpha']['licenseDeclared'].startswith('((GPL-2.0-or-later OR Artistic-2.0) AND BSD-3-Clause)'), p['alpha']['licenseDeclared']   # DEP-5: a comma before "and" lowers its priority
assert 'LicenseRef-Strange-1.0' in p['alpha']['licenseDeclared'], p['alpha']['licenseDeclared']
assert 'GPL-2.0-or-later' in p['alpha']['licenseDeclared'] and 'BSD-3-Clause' in p['alpha']['licenseDeclared']
assert p['alpha-lc-hr']['licenseDeclared'] == 'NOASSERTION'   # free-form copyright file
assert p['alpha-data']['licenseDeclared'] == 'NOASSERTION'    # symlink to a sibling that has none
assert p['alpha-dbgsym']['licenseDeclared'] == p['alpha']['licenseDeclared'], p['alpha-dbgsym']['licenseDeclared']   # doc directory symlink
assert p['beta']['licenseDeclared'].endswith('AND MIT')
assert any('sparky:lean-code' in a['comment'] for a in p['alpha']['annotations'])
assert 'LicenseRef-LLVM-exception' in p['alpha']['licenseDeclared'], p['alpha']['licenseDeclared']   # a bare exception id is no licence (found on the real cohort)
assert p['alpha']['originator'] == 'Organization: Debian'
assert '@' not in ' '.join(e['extractedText'] for e in d['hasExtractedLicensingInfos']), 'a contact leaked from a licence text'
assert 'Capitain_Jack' not in json.dumps(d) and 'lists.debian.org' not in json.dumps(d), 'a contact leaked'
assert {e['licenseId'] for e in d['hasExtractedLicensingInfos']} == {'LicenseRef-Strange-1.0', 'LicenseRef-LLVM-exception'}
P
expect green "the cohort replaces beta 2.0 by 2.1" $PY -I -c "
import json,sys
d=json.load(open('$W/sbom-next.json')); v=[p['versionInfo'] for p in d['packages'] if p['name']=='beta' and p['SPDXID'].startswith('SPDXRef-Pkg')]; assert v==['2.1'], v"
expect green "provenance facts" $PY -I - "$W/prov" <<'P'
import json, sys, glob
s = {f.split('/')[-1]: json.load(open(f)) for f in glob.glob(sys.argv[1] + '/*.intoto.json')}
a = s['fixsrc_1.0-1+stereo3d1+lc1_amd64.intoto.json']
names = [x['name'] for x in a['subject']]
assert names == ['alpha-data_1.0-1+stereo3d1+lc1_all.deb', 'alpha-dbgsym_1.0-1+stereo3d1+lc1_amd64.deb', 'alpha-lc-hr_1.0-1+stereo3d1+lc1_amd64.deb', 'alpha_1.0-1+stereo3d1+lc1_amd64.deb'], names
rd = a['predicate']['buildDefinition']['resolvedDependencies']
assert any(r.get('uri') == 'pkg:deb/debian/libc6@2.42-1?arch=amd64' for r in rd)
assert any(r.get('annotations', {}).get('role') == 'source-file' for r in rd)
assert a['predicate']['runDetails']['metadata']['finishedOn'] == '2026-11-04T02:27:17Z'
b = s['beta_2.0_amd64.intoto.json']
assert b['predicate']['buildDefinition']['internalParameters']['buildinfo']['present'] is False
P
expect green "gaps are listed, not filled" $PY -I -c "
import json
r=json.load(open('$W/prov.report.json')); g=r['gaps_by_recipe']
k = [x for x in g if x.endswith('/fixsrc')][0]
assert 'recipe-commit' in g[k]['gaps'] and 'build-environment' not in g[k]['gaps']
assert 'recipe-unresolved' in g['unresolved:beta']['gaps'] and 'build-environment' in g['unresolved:beta']['gaps']"

# red: the validators must fail on broken copies
$PY -I - "$W" <<'P'
import json, sys, shutil, glob
w = sys.argv[1]
d = json.load(open(w + '/sbom.json'))
b = json.loads(json.dumps(d)); b['packages'][3]['licenseDeclared'] = 'GPL-2.0-or-later AND AND'; json.dump(b, open(w + '/bad-licence.spdx.json', 'w'))
b = json.loads(json.dumps(d)); b['relationships'][0]['relatedSpdxElement'] = 'SPDXRef-nothing'; json.dump(b, open(w + '/bad-rel.spdx.json', 'w'))
b = json.loads(json.dumps(d))
for p in b['packages']:
    if p['name'] == 'beta': p['checksums'][0]['checksumValue'] = '0' * 64
json.dump(b, open(w + '/bad-sha.spdx.json', 'w'))
b = json.loads(json.dumps(d)); b['packages'] = [p for p in b['packages'] if p['name'] != 'beta']; b['relationships'] = [r for r in b['relationships'] if 'beta' not in r['relatedSpdxElement']]; json.dump(b, open(w + '/missing.spdx.json', 'w'))
shutil.copytree(w + '/prov', w + '/prov-unknown'); shutil.copytree(w + '/prov', w + '/prov-sha'); shutil.copytree(w + '/prov', w + '/prov-builder')
f = glob.glob(w + '/prov-unknown/fixsrc*')[0]; x = json.load(open(f)); x['predicate']['buildDefinition']['madeUp'] = 1; json.dump(x, open(f, 'w'))
f = glob.glob(w + '/prov-sha/fixsrc*')[0]; x = json.load(open(f)); x['subject'][0]['digest']['sha256'] = '1' * 64; json.dump(x, open(f, 'w'))
f = glob.glob(w + '/prov-builder/fixsrc*')[0]; x = json.load(open(f)); del x['predicate']['runDetails']['builder']; json.dump(x, open(f, 'w'))
P
expect red "SPDX: invalid licence expression"  $PY "$R/check-supply-chain.py" sbom "$W/bad-licence.spdx.json"
expect red "SPDX: relationship to nothing"     $PY "$R/check-supply-chain.py" sbom "$W/bad-rel.spdx.json"
expect red "SPDX: sha256 differs from the tree" $PY "$R/check-supply-chain.py" sbom "$W/bad-sha.spdx.json" --tree "$W/tree"
expect red "SPDX: a tree package is missing"   $PY "$R/check-supply-chain.py" sbom "$W/missing.spdx.json" --tree "$W/tree"
expect red "in-toto: unknown predicate field"  $PY "$R/check-supply-chain.py" provenance "$W/prov-unknown"
expect red "in-toto: subject digest differs from the tree" $PY "$R/check-supply-chain.py" provenance "$W/prov-sha" --tree "$W/tree"
expect red "SLSA: builder.id missing"          $PY "$R/check-supply-chain.py" provenance "$W/prov-builder"
expect red "make-sbom: cohort file changed"    bash -c "echo x >> '$W/cohort/beta_2.1_amd64.deb'; $PY '$R/make-sbom.py' --tree '$W/tree' --cohort-list '$W/cohort.list' --cohort-sha256 '$W/cohort.sha256' --name x --out '$W/x.json'"

# ORDER 394b: a build record beside the .deb files closes the four gaps; a damaged or missing fact is red
mkdir -p "$W/rec"
$PY -I - "$W" "$A" <<'P'
import json, sys
w, alpha = sys.argv[1:3]
rec = {'format': 'sparky-build-record/1', 'source': 'fixsrc', 'version': '1.0-1+stereo3d1+lc1', 'buildArchitecture': 'amd64',
       'recipeCommit': 'a' * 40, 'recipeDirty': False, 'builderImage': 'sha256:' + 'b' * 64, 'builderImageName': 'builder:1',
       'invocationId': '0b0e86c3-6c0a-4d6a-9d57-0f5f0a1d7f10', 'startedOn': '2026-11-04T02:00:00Z', 'startBasis': 'build-script',
       'finishedOn': '2026-11-04T02:30:00Z', 'debs': [{'name': 'alpha_1.0-1+stereo3d1+lc1_amd64.deb', 'sha256': alpha}],
       'files': [], 'unrecorded': []}
name = 'fixsrc_1.0-1+stereo3d1+lc1_amd64.sparky-build.json'
def put(folder, **change):
    import os
    r = json.loads(json.dumps(rec))
    for k, v in change.items():
        if v is None: r.pop(k, None)
        else: r[k] = v
    os.makedirs(w + '/' + folder, exist_ok=True)
    json.dump(r, open(w + '/' + folder + '/' + name, 'w'))
put('rec')
put('rec-damaged', recipeCommit=None, recipeDirty=None)                       # absent and not listed as unrecorded
put('rec-unrecorded', recipeCommit=None, recipeDirty=None, unrecorded=['recipeCommit'])
put('rec-badcommit', recipeCommit='main')
put('rec-bothways', unrecorded=['invocationId'])
P
prov() { $PY "$R/make-provenance.py" --tree "$W/tree" --build-dir "$W/bi" --build-dir "$1" --recipes-dir "$W/recipes" --recipes-dir "$W/empty" --out-dir "$2" --report "$2.report.json"; }
expect green "make-provenance with a build record"  prov "$W/rec" "$W/prov-rec"
expect green "check provenance --require-recorded for the recorded source" $PY "$R/check-supply-chain.py" provenance "$W/prov-rec" --tree "$W/tree" --require-recorded --only-source fixsrc
expect green "the record's facts are in the statement" $PY -I - "$W/prov-rec" "$W/prov-rec.report.json" <<'P'
import glob, json, sys
a = json.load(open(glob.glob(sys.argv[1] + '/fixsrc*')[0]))
rd = a['predicate']['buildDefinition']['resolvedDependencies']
repo = [r for r in rd if r.get('annotations', {}).get('role') == 'recipe-repository']
assert repo and repo[0]['digest'] == {'gitCommit': 'a' * 40} and repo[0]['annotations']['worktreeDiffersFromCommit'] is False, rd
run = a['predicate']['runDetails']
assert run['builder']['builderDependencies'][0]['digest'] == {'sha256': 'b' * 64}, run['builder']
assert run['metadata'] == {'invocationId': '0b0e86c3-6c0a-4d6a-9d57-0f5f0a1d7f10', 'startedOn': '2026-11-04T02:00:00Z', 'finishedOn': '2026-11-04T02:30:00Z'}, run['metadata']
rep = json.load(open(sys.argv[2]))
k = [x for x in rep['gaps_by_recipe'] if x.endswith('/fixsrc')][0]
gaps = rep['gaps_by_recipe'][k]['gaps']
assert not {'recipe-commit', 'builder-image-digest', 'build-start-time', 'invocation-id'} & set(gaps), gaps
assert rep['gaps_by_recipe']['unresolved:beta']['gaps'].count('recipe-commit') == 1     # no record: the gaps stay
assert rep['statements_with_build_record'] == 1 and rep['build_records_read'] == 1
P
expect red "make-provenance: a record lacking a fact it did not list as unrecorded" prov "$W/rec-damaged" "$W/prov-damaged"
expect red "make-provenance: a malformed commit"      prov "$W/rec-badcommit" "$W/prov-badcommit"
expect red "make-provenance: recorded and unrecorded at once" prov "$W/rec-bothways" "$W/prov-bothways"
expect green "make-provenance: an unrecorded fact is allowed" prov "$W/rec-unrecorded" "$W/prov-unrec"
expect red "check --require-recorded: the commit is unrecorded" $PY "$R/check-supply-chain.py" provenance "$W/prov-unrec" --require-recorded --only-source fixsrc
expect red "check --require-recorded: no record at all" $PY "$R/check-supply-chain.py" provenance "$W/prov" --require-recorded --only-source fixsrc
expect green "check without --require-recorded accepts a statement with gaps" $PY "$R/check-supply-chain.py" provenance "$W/prov-unrec"

[ $fail = 0 ] && echo "ALL PASS" || { echo "FAILED"; exit 1; }
