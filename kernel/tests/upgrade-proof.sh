#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# upgrade-proof.sh PUBLISHED_REPO CANDIDATE_DIR IMAGE OUT_DIR: a kernel build's upgrade, read on apt's Inst and Remv lines.
#
# Each case is a fresh Debian testing amd64 container (IMAGE, pinned by digest) with Debian's archive over HTTPS and the
# edition's published repository read from a local copy (PUBLISHED_REPO: dists/mashtabba and pool, signed; file: source, the
# edition's 1001 pin on its origin), never the network repository. It installs what an edition system has of the kernel: the
# image and headers metas of FLAVOURS (default all three) and libc6-dev (so linux-libc-dev is there), as published. Then:
#   control  the published repository alone: apt-get -s full-upgrade must name no package of the candidate build;
#   upgrade  the candidate build's packages (CANDIDATE_DIR: images, headers, metas, linux-libc-dev and its cross packages,
#            no -lc-hr companions needed) as a second local archive of the same origin: apt-get -s full-upgrade must install
#            every candidate package the metas and libc6-dev reach and remove nothing; the full upgrade then runs, and
#            dpkg --audit must be empty and every candidate package installed.
#   from     (ORDER 636) an earlier build that is not published yet first: the .deb files under FROM_DIR (searched recursively,
#            a stage's folders included; mounted read-only, never changed) as a local archive of the same origin, a full
#            upgrade to them, which must install some of them and remove nothing; then the candidate exactly as in upgrade.
# OUT_DIR gets one log per case (the Inst and Remv lines, apt's exit status, dpkg --audit). Exit status 1 on any failure.
# NAME_PREFIX names the containers (default upgrade-proof); FLAVOURS selects flavours (base, v3, rt); CASES selects cases
# (default control upgrade, plus from when FROM_DIR is set).
set -eu
REPO=$(readlink -f "${1:?usage: upgrade-proof.sh PUBLISHED_REPO CANDIDATE_DIR IMAGE OUT_DIR}")
CAND=$(readlink -f "${2:?candidate dir}")
IMAGE=${3:?image}
OUT=$(readlink -f "${4:?out dir}")
FLAVOURS=${FLAVOURS:-base v3 rt}
PREFIX=${NAME_PREFIX:-upgrade-proof}
FROM=; FROMMOUNT=
if [ -n "${FROM_DIR:-}" ]; then FROM=$(readlink -f "$FROM_DIR"); FROMMOUNT="-v $FROM:/proof/from:ro"; fi
mkdir -p "$OUT"
HERE=$(dirname "$(readlink -f "$0")")
metas=
for f in $FLAVOURS; do
	case $f in base) s=;; v3) s=-v3;; rt) s=-rt;; *) echo "upgrade-proof: unknown flavour $f" >&2; exit 2;; esac
	metas="$metas linux-image-sparky-stereo$s linux-headers-sparky-stereo$s"
done
INNER='
set -u
sh /run/https-only-apt.sh >/dev/null || exit 1
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8
cp /proof/repo/sparky-stereo-repo.asc /usr/share/keyrings/
printf "Types: deb\nURIs: file:/proof/repo\nSuites: mashtabba\nComponents: main\nSigned-By: /usr/share/keyrings/sparky-stereo-repo.asc\n" > /etc/apt/sources.list.d/sparky.sources
printf "Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n" > /etc/apt/preferences.d/sparky
apt-get -y update >/dev/null 2>&1 || { echo "FAIL: apt-get update"; exit 1; }
for deb in /proof/candidate/*.deb; do case $deb in *-lc-hr_*) continue;; esac; echo "$(dpkg-deb -f "$deb" Package) $(dpkg-deb -f "$deb" Version)"; done > /tmp/cand.txt
echo "candidate packages: $(wc -l < /tmp/cand.txt)"
apt-get -y install apt-utils >/dev/null 2>&1
apt-get -y install --no-install-recommends $METAS libc6-dev > /proof/out/$CASE.install.log 2>&1 || { echo "FAIL: installing the published metas"; tail -n 5 /proof/out/$CASE.install.log; exit 1; }
echo "published: $(dpkg-query -W -f="\${Package} \${Version}\n" $METAS linux-libc-dev | tr "\n" ";")"
if [ "$CASE" = from ]; then
	[ -d /proof/from ] || { echo "FAIL: the from case needs FROM_DIR"; exit 1; }
	mkdir -p /srv/from && find /proof/from -name "*.deb" ! -name "*-lc-hr_*" -exec cp {} /srv/from/ \;
	for deb in /srv/from/*.deb; do echo "$(dpkg-deb -f "$deb" Package) $(dpkg-deb -f "$deb" Version)"; done > /tmp/from.txt
	(cd /srv/from && apt-ftparchive packages . > Packages && apt-ftparchive -o APT::FTPArchive::Release::Origin="Sparky Stereo OS" \
		-o APT::FTPArchive::Release::Label="Sparky Stereo OS earlier build" -o APT::FTPArchive::Release::Suite=mashtabba \
		-o APT::FTPArchive::Release::Codename=mashtabba release . > Release)
	echo "deb [trusted=yes] file:/srv/from ./" > /etc/apt/sources.list.d/from.list
	apt-get -y update >/dev/null 2>&1 || { echo "FAIL: apt-get update with the earlier build"; exit 1; }
	apt-get -y full-upgrade > /proof/out/$CASE.first-upgrade.log 2>&1 || { echo "FAIL: the upgrade to the earlier build"; tail -n 20 /proof/out/$CASE.first-upgrade.log; exit 1; }
	grep -E "^(Remv|Removing|Purg)" /proof/out/$CASE.first-upgrade.log && { echo "FAIL: the upgrade to the earlier build removes packages"; exit 1; }
	first=0
	while read -r p v; do [ "$(dpkg-query -W -f="\${Status} \${Version}" "$p" 2>/dev/null)" = "install ok installed $v" ] && { echo "earlier build installed $p $v"; first=$((first + 1)); }; done < /tmp/from.txt
	[ "$first" -gt 0 ] || { echo "FAIL: nothing of the earlier build was installed"; exit 1; }
	echo "earlier: $(dpkg-query -W -f="\${Package} \${Version}\n" $METAS linux-libc-dev | tr "\n" ";")"
fi
if [ "$CASE" != control ]; then
	mkdir -p /srv/cand && cp /proof/candidate/*.deb /srv/cand/ && rm -f /srv/cand/*-lc-hr_*
	(cd /srv/cand && apt-ftparchive packages . > Packages && apt-ftparchive -o APT::FTPArchive::Release::Origin="Sparky Stereo OS" \
		-o APT::FTPArchive::Release::Label="Sparky Stereo OS candidate" -o APT::FTPArchive::Release::Suite=mashtabba \
		-o APT::FTPArchive::Release::Codename=mashtabba release . > Release)
	echo "deb [trusted=yes] file:/srv/cand ./" > /etc/apt/sources.list.d/cand.list
	apt-get -y update >/dev/null 2>&1 || { echo "FAIL: apt-get update with the candidate"; exit 1; }
fi
apt-get -s full-upgrade > /proof/out/$CASE.simulate.log 2>&1; rc=$?
echo "simulate exit $rc"
grep -E "^(Inst|Remv|Purg)" /proof/out/$CASE.simulate.log > /proof/out/$CASE.inst-remv.txt || true
inst=$(grep -c "^Inst" /proof/out/$CASE.simulate.log || true); remv=$(grep -c -E "^(Remv|Purg)" /proof/out/$CASE.simulate.log || true)
awk "NR==FNR { want[\$1 \" \" \$2] = 1; next } /^Inst / { v = \$0; sub(/^[^(]*\\(/, \"\", v); sub(/ .*/, \"\", v); if ((\$2 \" \" v) in want) print \$2, v }" /tmp/cand.txt /proof/out/$CASE.simulate.log > /proof/out/$CASE.candidate-inst.txt
ours=$(wc -l < /proof/out/$CASE.candidate-inst.txt)
echo "Inst $inst, Remv $remv, of the candidate build $ours"
cat /proof/out/$CASE.candidate-inst.txt
[ "$rc" -eq 0 ] || exit 1
[ "$remv" -eq 0 ] || { echo "FAIL: the upgrade removes packages"; exit 1; }
if [ "$CASE" = control ]; then
	[ "$ours" -eq 0 ] || { echo "FAIL: the control installs the candidate build"; exit 1; }
	echo "PASS control"; exit 0
fi
[ "$ours" -gt 0 ] || { echo "FAIL: the upgrade installs nothing of the candidate build"; exit 1; }
apt-get -y full-upgrade > /proof/out/$CASE.full-upgrade.log 2>&1; rc=$?
echo "full-upgrade exit $rc"; [ "$rc" -eq 0 ] || { tail -n 20 /proof/out/$CASE.full-upgrade.log; exit 1; }
audit=$(dpkg --audit 2>&1); echo "dpkg --audit: ${audit:-empty}"; [ -z "$audit" ] || exit 1
missing=0
for deb in /srv/cand/*.deb; do
	p=$(dpkg-deb -f "$deb" Package); v=$(dpkg-deb -f "$deb" Version)
	if [ "$(dpkg-query -W -f="\${Status} \${Version}" "$p" 2>/dev/null)" = "install ok installed $v" ]; then echo "installed $p $v"
	elif grep -q -E "^Inst $p " /proof/out/$CASE.simulate.log; then echo "MISSING $p $v"; missing=$((missing + 1))
	else echo "not reached $p (no installed package needs it)"; fi
done
[ "$missing" -eq 0 ] || exit 1
echo "PASS $CASE"
'
status=0
for case in ${CASES:-control upgrade${FROM:+ from}}; do
	docker run --rm --name "$PREFIX-$case" --ulimit core=0 --platform linux/amd64 --cpus 4 --memory 4g \
		-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$HERE/../../tools/https-only-apt.sh":/run/https-only-apt.sh:ro \
		-v "$REPO":/proof/repo:ro -v "$CAND":/proof/candidate:ro $FROMMOUNT -v "$OUT":/proof/out \
		-e CASE="$case" -e METAS="$metas" "$IMAGE" sh -c "$INNER" > "$OUT/$case.log" 2>&1 || status=1
	echo "$case: $(tail -n 1 "$OUT/$case.log")"
done
exit $status
