#!/bin/bash
# One of the edition's own source packages at x86-64-v3, written as a variant at BUILD time (ORDER 108, milestone 5 part B). The same steps as mesa-v3.sh,
# for a source whose debian/rules is Debian's own shape (gl-stereo: dpkg's buildflags.mk). The source is unpacked as it is; debian/rules, the patches and the
# Lean Code pipeline are untouched. The recipe's steps on the source are only these:
#   - XB-Architecture-Variant: amd64v3 in every binary stanza of debian/control and of debian/control.in (debian/rules regenerates the first from the
#     second), which dpkg-gencontrol copies into each binary package's control file;
#   - -march=x86-64-v3 through DEB_CFLAGS_APPEND and DEB_CXXFLAGS_APPEND (the user-level variables, applied after the maintainer's): Mesa's debian/rules
#     assigns DEB_CFLAGS_MAINT_APPEND := -Wall, which throws away the value of that variable from the environment, so the *_MAINT_APPEND route the
#     libstereo-av1 build uses compiles at the baseline here without a word; and -C target-cpu=x86-64-v3 for the Rust parts (NVK, Rusticl) through
#     RUSTFLAGS; the optimisation level stays Debian's (no -O3, tests on, warnings on). The build fails if -march=x86-64-v3 is not on the compile lines;
#   - the link and start gate runs with the toolkit that leaves Architecture-Variant out of its local index (lean/archive.py), so the source package's
#     older copy of the whole lean/ folder is replaced by the build tree's (as a toolkit release will; the two files alone are not enough for a source
#     whose copy is older than lean/parallel.py: ImportError: cannot import name 'parallel').
# Run as root in a container (network for Debian, deb-multimedia and Sparky; --cpus 2); the compile, the record and the gate run as the build user.
# Mounts: /dsc (the folder with the +stereo3d25+lc1 .dsc, .orig and .debian tarballs), /prev (the baseline amd64 .deb set of the same version, for the gate),
# /archive (sources.json and keys), /repo (the published tree), /toolkit (sparky-os of the build tree), /work (output, owned by the build user).
# Env: SRC_DSC (file name of the .dsc), JOBS (default 2), NOCHECK=1 (skip dh_auto_test: only where the same tests fail in the same way on the baseline build in this
# container, shown by a control run without -march; say so in the report), MIN_MARCH (the least number of compile lines that must carry -march=x86-64-v3, default 5).
set -euo pipefail
sh /run/https-only-apt.sh >/dev/null
export DEBIAN_FRONTEND=noninteractive HOME=/tmp
printf 'deb [trusted=yes] file:/repo mashtabba main\n' >/etc/apt/sources.list.d/sparky.list
printf 'Types: deb\nURIs: https://www.deb-multimedia.org\nSuites: forky\nComponents: main non-free\nSigned-By: /archive/dmo.pgp\n' >/etc/apt/sources.list.d/dmo.sources
apt-get -y -qq update >/dev/null 2>&1
apt-get -y -qq --no-install-recommends install ca-certificates dpkg-dev devscripts equivs bubblewrap gnupg binutils git quilt python3 python3-yaml node-acorn nodejs perl gcc sudo >/work/apt-tools.log 2>&1
id builder >/dev/null 2>&1 || useradd --create-home --uid 1000 builder
mkdir -p /work/lcscratch /work/out /work/src
chown -R builder:builder /work
cd /work
runuser -u builder -- dpkg-source -x "/dsc/$SRC_DSC" src/pkg >/work/unpack.log 2>&1
cd src/pkg
for f in debian/control debian/control.in; do
	[ -f "$f" ] || continue
	awk '/^Package: / {print; print "XB-Architecture-Variant: amd64v3"; next} {print}' "$f" >"$f.new" && mv "$f.new" "$f"
done
cp /toolkit/lean/*.py /toolkit/lean/*.tsv /toolkit/lean/*.java /toolkit/lean/*.zig debian/sparky-lean-toolkit/lean/
chown -R builder:builder /work
mk-build-deps -r -i -t "apt-get -y -qq --no-install-recommends" debian/control >/work/builddeps.log 2>&1 || { tail -8 /work/builddeps.log; exit 1; }
echo "build dependencies installed: $(grep -c '^Setting up' /work/builddeps.log)"
rm -f /work/src/pkg/*-build-deps_*.deb /work/src/pkg/*-build-deps_*.buildinfo /work/src/pkg/*-build-deps_*.changes 2>/dev/null || true
cat >/work/job.sh <<'JOB'
set -euo pipefail
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
export SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json SPARKY_LC_SCRATCH=/work/lcscratch SPARKY_LC_PREVIOUS_DIR=/prev
export DEB_BUILD_OPTIONS="parallel=${JOBS:-2}${NOCHECK:+ nocheck}"
export DEB_CFLAGS_APPEND="-march=x86-64-v3" DEB_CXXFLAGS_APPEND="-march=x86-64-v3" RUSTFLAGS="-C target-cpu=x86-64-v3"
cd /work/src/pkg
start=$(date +%s)
dpkg-buildpackage -B -us -uc -d -j"${JOBS:-2}" >>/work/build-v3.log 2>&1 && echo "v3 build exit=0" || { echo "v3 build FAILED"; exit 1; }
echo "v3 build seconds: $(( $(date +%s) - start ))"
n=$(grep -c -- "-march=x86-64-v3" /work/build-v3.log || true); echo "compile lines with -march=x86-64-v3: $n"
[ "$n" -gt "${MIN_MARCH:-5}" ] || { echo "march=x86-64-v3 never reached the compiler"; exit 1; }
cd /work/src
mv ./*.deb ./*.buildinfo ./*.changes /work/out/ 2>/dev/null || true
cd /work/out
PYTHONPATH=/toolkit python3 -B -m lean.release check-debs ./*+lc1_*.deb && echo "check-debs exit=0" || echo "check-debs FAILED"
PYTHONPATH=/toolkit python3 -B -m lean.release check-link ./*+lc1_*.deb --previous-dir /prev && echo "check-link exit=0" || echo "check-link FAILED"
JOB
runuser -u builder -- env JOBS="${JOBS:-2}" bash /work/job.sh
ls /work/out | head -60
for d in /work/out/*.deb; do printf '%s: Architecture-Variant=%s\n' "$(basename "$d")" "$(dpkg-deb -f "$d" Architecture-Variant)"; done | head -40
