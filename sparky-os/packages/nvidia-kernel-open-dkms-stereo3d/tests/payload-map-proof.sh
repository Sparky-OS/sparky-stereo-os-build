#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/01
# Copyright 2026 under the GNU GPL3 License
# payload-map-proof.sh DSC OUT: red and green for debian/sparky-lean-payload-sources.json (ORDER 311).
# nvidia-kernel-open-dkms-stereo3d installs a copy of its source tree in /usr/src/nvidia-VERSION. Without a payload map,
# lean.debhelper restores the authored text of those copies by content hash before the payload pass; when the native pass
# has made comment-only files identical to files the source ships empty, the hash restore fills the empty ones (the
# published 615.71.09-2+stereo3d6+lc1, built by toolkit 0.1.15, carries three such files). With the map, the restore goes
# by path. The proof builds the given published lc1 source twice in fresh Debian testing containers, as published and with
# this recipe's map added, and compares every file of the installed copy, its authored text taken from the HR companion,
# with the source tree: red, the published source, some differ; green, with the map, none differ.
# The link and start gate of lean.debhelper is not run (it needs a publication's archive universe and changes no bytes).
set -euo pipefail
DSC=$(readlink -f "${1:?usage: payload-map-proof.sh DSC OUT}")
OUT=$(mkdir -p "${2:?usage: payload-map-proof.sh DSC OUT}" && cd "$2" && pwd)
HERE=$(cd "$(dirname "$0")/.." && pwd)
IMG=${IMG:-debian@sha256:fe4be93b807e7d05dccdaf54931173d9368b349f91a8170dadd787213aa3bf19}
for case in published map; do
	mkdir -p "$OUT/$case"
	docker run --rm --platform linux/amd64 --cpus 4 -e CASE=$case -v "$(dirname "$DSC")":/in:ro -v "$OUT/$case":/out \
		-v "$HERE/debian/sparky-lean-payload-sources.json":/map.json:ro "$IMG" bash -c '
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8 DEBFULLNAME="Daniel Ramos (Capitain Jack)" DEBEMAIL=Capitain_Jack@yahoo.com
apt-get -qq update >/dev/null
apt-get -y -qq --no-install-recommends install build-essential devscripts equivs dpkg-dev fakeroot python3 python3-yaml nodejs node-acorn perl gcc >/out/00-tools.log 2>&1
mkdir -p /build && cd /build
dpkg-source -x /in/'"$(basename "$DSC")"' src >/out/01-extract.log 2>&1
cp -a src tree
cd src
[ "$CASE" = map ] && cp /map.json debian/sparky-lean-payload-sources.json
mk-build-deps -i -r -t "apt-get -y -q --no-install-recommends" debian/control >/out/02-deps.log 2>&1
cat >/build/builddeb.py <<PY
import sys
from pathlib import Path
root = Path(sys.argv[1])
sys.path.insert(0, str(root / "debian/sparky-lean-toolkit"))
from lean import debhelper
debhelper.link_gate = lambda built: print("link gate not run here")
debhelper.build(root, root / "debian/sparky-lean-toolkit/provenance.sh")
PY
sed -i "s|^\tPYTHONPATH=\$(CURDIR)/debian/sparky-lean-toolkit python3 -m lean.debhelper --provenance .*$|\tpython3 /build/builddeb.py \$(CURDIR)|" debian/rules
export SOURCE_DATE_EPOCH=$(dpkg-parsechangelog -STimestamp)
{ debian/rules clean && debian/rules build && fakeroot debian/rules binary; } >/out/03-build.log 2>&1
cd /build
python3 - >/out/compare.txt <<PY
import glob, hashlib, json, lzma, os, subprocess, tempfile
deb = glob.glob("/build/nvidia-kernel-open-dkms-stereo3d_*.deb")[0]
hr = glob.glob("/build/nvidia-kernel-open-dkms-stereo3d-lc-hr_*.deb")[0]
d, h = tempfile.mkdtemp(), tempfile.mkdtemp()
subprocess.run(["dpkg-deb", "-x", deb, d], check=True); subprocess.run(["dpkg-deb", "-x", hr, h], check=True)
p, a = "nvidia-kernel-open-dkms-stereo3d", "amd64"
m = json.load(open(f"{d}/usr/share/dpkg-stereo/lc/{p}/{a}.json"))
src = glob.glob(f"{d}/usr/src/nvidia-*")[0]
pre = src[len(d):] + "/"
same, differ = 0, []
for r in m["files"]:
    if r["kind"] != "file" or not r["path"].startswith(pre):
        continue
    if r["status"] == "projected":
        data = lzma.decompress(open(f"{h}/usr/share/dpkg-stereo/hr/{p}/{a}/{r["sha_hr"]}.xz", "rb").read())
    else:
        data = open(d + r["path"], "rb").read()
    ref = os.path.join("/build/tree", r["path"][len(pre):])
    if not os.path.isfile(ref):
        continue
    if data == open(ref, "rb").read():
        same += 1
    else:
        differ.append(r["path"][len(pre):])
print(f"{os.environ["CASE"]}: {same} installed source files equal the source tree, {len(differ)} differ {differ[:10]}")
PY
grep -h "Restored" /out/03-build.log >>/out/compare.txt || true
chown -R '"$(id -u):$(id -g)"' /out' || { echo "FAIL $case build"; tail -5 "$OUT/$case/03-build.log"; exit 1; }
	cat "$OUT/$case/compare.txt"
done
red=$(sed -n 's/^published: .* equal the source tree, \([0-9]*\) differ.*/\1/p' "$OUT/published/compare.txt")
green=$(sed -n 's/^map: .* equal the source tree, \([0-9]*\) differ.*/\1/p' "$OUT/map/compare.txt")
echo "published source: $red files of the installed copy differ from the source tree; with the map: $green"
[ "$green" = 0 ] || exit 1
