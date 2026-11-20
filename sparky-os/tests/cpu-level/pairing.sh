#!/bin/bash
# lean.release check-debs with a variant and its -lc-hr companion (ORDER 108). The real published lc1 archives libstereo-av-dev,
# libstereo-av-dev-lc-hr and libstereo-av1 stand for a baseline set; the variant set is the same three repacked with
# Architecture-Variant: amd64v3 in their control files and named _amd64v3.deb (what a variant build leaves, apart from the code).
# Usage: pairing.sh PUBLISHED_TREE OLD_SPARKY_OS WORK   (DOCKER_HOST set; IMAGE defaults to gr108-base:testing-20261027)
set -uo pipefail
TREE=${1:?published tree}; OLD=${2:?sparky-os subset from before the change}; WORK=${3:?work folder}
IMAGE=${IMAGE:-gr108-base:testing-20261027}
HERE=$(cd "$(dirname "$0")" && pwd); NEW=$(cd "$HERE/../.." && pwd)
mkdir -p "$WORK"
docker run --rm --cpus 2 --ulimit core=1 --name gr108-pair -e DEBIAN_FRONTEND=noninteractive -v "$TREE:/tree:ro" -v "$OLD:/old:ro" -v "$NEW:/new:ro" \
	-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v /K3D/partners/https-only-apt.sh:/run/https-only-apt.sh:ro -v "$WORK:/work" "$IMAGE" bash -c '
sh /run/https-only-apt.sh >/dev/null; apt-get -y update >/dev/null 2>&1; apt-get -y install python3 >/dev/null 2>&1
failed=0; ok() { echo "PASS $*"; }; bad() { echo "FAIL $*"; failed=1; }
W=/work/pair; rm -rf $W; mkdir -p $W/base $W/var; P=/tree/pool/main/s/stereo-layer
for p in libstereo-av-dev libstereo-av-dev-lc-hr libstereo-av1; do cp $P/${p}_1.18.0-1+lc1_amd64.deb $W/base/; done
for d in $W/base/*.deb; do
	n=$(basename $d _amd64.deb); t=$W/x-$n; dpkg-deb -R $d $t; printf "Architecture-Variant: amd64v3\n" >>$t/DEBIAN/control
	dpkg-deb --root-owner-group -b $t $W/var/${n}_amd64v3.deb >/dev/null
done
chk() { (cd /$1 && python3 -B -m lean.release check-debs --no-record "${@:2}" 2>&1 | tail -1); }
out=$(chk old $W/base/*.deb); echo "$out" | grep -q "verified 3 packages" && ok "the baseline set passes (old toolkit): $out" || bad "baseline set: $out"
out=$(chk old $W/var/*.deb); echo "$out" | grep -q "verified 3 packages" && ok "the variant set alone passes (old toolkit): $out" || bad "variant set: $out"
out=$(chk old $W/base/*.deb $W/var/*.deb); echo "$out" | grep -q "duplicate package identity" && ok "red: both sets together stop (old toolkit): $out" || bad "old toolkit on both sets: $out"
out=$(chk new $W/base/*.deb $W/var/*.deb); echo "$out" | grep -q "verified 6 packages" && ok "green: both sets together pass (new): $out" || bad "new toolkit on both sets: $out"
out=$(chk new $W/var/libstereo-av-dev_1.18.0-1+lc1_amd64v3.deb $W/base/libstereo-av-dev-lc-hr_1.18.0-1+lc1_amd64.deb); echo "$out" | grep -q "HR documentation package is missing" && ok "a variant with the baseline companion is refused (new): $out" || bad "mismatched companion: $out"
out=$(chk new $W/var/libstereo-av-dev_1.18.0-1+lc1_amd64v3.deb); echo "$out" | grep -q "HR documentation package is missing" && ok "a variant with no companion is refused (new)" || bad "no companion: $out"
exit $failed' 2>&1 | grep -E "^(PASS|FAIL)"
