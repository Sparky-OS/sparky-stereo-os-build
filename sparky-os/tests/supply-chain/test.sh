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
[ $fail = 0 ] && echo "ALL PASS" || { echo "FAILED"; exit 1; }
