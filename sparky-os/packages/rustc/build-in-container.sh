#!/bin/bash
# Sparky Stereo OS: rustc from Debian's rustc source package, with the standard library's runtime package, built with Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/11/12
# Copyright 2026 under the GNU GPL3 License
# Runs as root inside a clean Debian testing build container; build.sh starts it. /work is the job folder, /src Debian's
# rustc source package as apt-get source downloads it, /toolkit the build tree's sparky-os folder, /tools this folder,
# /seed (optional) the folder with the edition's previous compiler packages. VERSION_FILE names the versions file.
# Steps: deps (the edition's source packages and the build dependencies, with the network), build (dpkg-buildpackage,
# without network), repackage (after a "discover" build stopped
# at the standard library's hash: the source is made again with the hash and the compiled tree is packaged, not recompiled).
# Last update 2026/11/12
trap 'chown -R 1000:1000 /work/ 2>/dev/null || true' EXIT
set -euo pipefail
: "${SOURCE_DATE_EPOCH:?a source is dated by its recipe, never by the clock: run this through build.sh (sparky_provenance_init)}" "${SOURCE_DATE_RFC2822:?see SOURCE_DATE_EPOCH}"
: "${VERSION_FILE:?the versions file of the compiler to build}" "${STEP:?deps, build or repackage}"
# shellcheck disable=SC1090
. "$VERSION_FILE"
STD_HASH=${STD_HASH_FOUND:-$STD_HASH}
VERSION=$DEBIAN_VERSION+$EDITION
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS="parallel=4 ${SPARKY_RUSTC_BUILD_OPTIONS-nocheck}"
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com LC_ALL=C.UTF-8
# The compiler's own native inputs are the seven files of compiler/rustc_llvm/llvm-wrapper; they go through the C and
# C++ pass. Every other C-family file of the tree is read by something else than the C compiler of this build:
PRESERVE=(
	--preserve-source 'vendor/*' "vendored Cargo crates: each crate's .cargo-checksum.json binds its files' bytes"
	--preserve-source 'library/*' "shipped as source in rust-src: generator and test inputs (stdarch's intrinsics headers are parsed by stdarch-gen and stdarch-verify), an include_str! target (std's SGX entry.S) and a vendored crate"
	--preserve-source 'tests/*' "test fixtures: the compiler's test suite compares their lines and columns"
	--preserve-source 'src/*' "benchmark and CI inputs, not compiled in the package build"
	--preserve-source 'compiler/rustc_codegen_gcc/*' "a test fixture of a backend the package does not build"
)

make_source() {    # make_source HASH OUT: OUT/s1 gets the +stereo3dN source, OUT/lc the +stereo3dN+lc1 source
	local hash=$1 out=$2
	rm -rf "$out" && mkdir -p "$out/s1" "$out/lc"
	cd "$out/s1"
	echo "$DSC_SHA256  /src/rustc_$DEBIAN_VERSION.dsc" | sha256sum -c
	cp /src/rustc_"$DEBIAN_VERSION".dsc /src/rustc_"$DEBIAN_VERSION".debian.tar.xz /src/rustc_"${DEBIAN_VERSION%-*}".orig.tar.xz .
	dpkg-source -x "rustc_$DEBIAN_VERSION.dsc" t >/dev/null
	python3 /tools/edit-packaging.py t "$VERSION" "$hash" "$SEED_TEXT" /tools
	python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" t
	dpkg-source -b t >/dev/null
	rm -rf t
	cd "$out/lc"
	cp ../s1/rustc_"$VERSION".dsc ../s1/rustc_"$VERSION".debian.tar.xz ../s1/rustc_"${DEBIAN_VERSION%-*}".orig.tar.xz .
	dpkg-source -x "rustc_$VERSION.dsc" authored >/dev/null
	PYTHONPATH=/toolkit python3 -m lean.debian_prepare authored "$VERSION+lc1" --toolkit /toolkit "${PRESERVE[@]}"
	[ "$(grep -c 'python3 -m lean.debhelper --provenance' authored/debian/rules)" = 1 ]
	# The link and start gate runs on the finished packages after the build (as the dpkg recipe does): inside the build
	# the new compiler's own packages are not installable yet.
	cat >authored/debian/sparky-builddeb.py <<'PYWRAP'
import sys
from pathlib import Path
root = Path(sys.argv[1])
sys.path.insert(0, str(root / 'debian/sparky-lean-toolkit'))
from lean import debhelper, release
debhelper.link_gate = lambda built: print('link gate after the build: lean.release check-link', ' '.join(p.name for p in built))
# rust-src is the compiler's and the standard library's source, shipped as source: it stays as its authors ship it
RUST_SRC = {'/usr/src/rustc-*': "the compiler's and the standard library's source, shipped as source: cargo checks "
            "library/vendor against each crate's .cargo-checksum.json, rust-analyzer and -Zbuild-std read it, and its "
            'benchmark inputs hold scripts no installed interpreter parses (Python 2)'}
build_tree = release.build_tree
release.build_tree = lambda staging, out, preserve=None: build_tree(
    staging, out, preserve=RUST_SRC if Path(staging).name == 'rust-src' else preserve)
debhelper.build(root, root / 'debian/sparky-lean-toolkit/provenance.sh')
PYWRAP
	sed -i "s|^\tPYTHONPATH=\$(CURDIR)/debian/sparky-lean-toolkit python3 -m lean.debhelper --provenance .*\$|\tpython3 \$(CURDIR)/debian/sparky-builddeb.py \$(CURDIR)|" authored/debian/rules
	grep -q 'sparky-builddeb.py' authored/debian/rules
	python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" authored
	(cd authored && dpkg-source -b . >/dev/null)
	rm -rf authored
	(cd "$out" && sha256sum s1/*.dsc s1/*.debian.tar.xz lc/*+lc1.dsc lc/*+lc1.debian.tar.xz) | tee "$out/SOURCE-SHA256SUMS"
}

if [ "$STEP" = deps ]; then
	apt-get -y update >/work/apt-update.log 2>&1
	apt-get -y --no-install-recommends install devscripts dpkg-dev python3 >/work/bootstrap.log 2>&1
	if [ -d /seed ]; then
		# the edition's previous compiler is the only candidate for rustc and cargo: a build that would take Debian's stops
		mkdir -p /var/local/seed && cp /seed/*.deb /var/local/seed/
		(cd /var/local/seed && dpkg-scanpackages --multiversion . >Packages 2>/dev/null)
		echo 'deb [trusted=yes] file:/var/local/seed ./' >/etc/apt/sources.list.d/sparky-seed.list
		printf 'Package: *\nPin: origin ""\nPin-Priority: 1001\n' >/etc/apt/preferences.d/sparky-seed
		apt-get -y update >>/work/apt-update.log 2>&1
	fi
fi
seed=$(apt-cache policy rustc | awk '/Candidate:/ {print $2}')
SEED_TEXT="Debian testing's rustc $seed"
if [ -e /etc/apt/sources.list.d/sparky-seed.list ]; then
	case $seed in *+stereo3d*) ;; *) echo "the edition's seed compiler is not the candidate (rustc candidate: $seed): refusing to build with Debian's" >&2; exit 1 ;; esac
	SEED_TEXT="the edition's rustc $seed"
fi

case $STEP in
deps)    # needs the network (apt); the driver commits the result as the image the build runs in, without network
	make_source "$STD_HASH" /work/source
	apt-get -y --no-install-recommends build-dep "/work/source/lc/rustc_$VERSION+lc1.dsc" >/work/build-dep.log 2>&1
	dpkg-query -W -f '${Package} ${Version}\n' rustc cargo libstd-rust-dev llvm-22-dev libllvm22 gcc g++ cmake python3 wasi-libc debhelper dpkg-dev >/work/build-toolchain.txt
	if [ -e /etc/apt/sources.list.d/sparky-seed.list ]; then grep -q '^rustc .*+stereo3d' /work/build-toolchain.txt || { echo "the installed rustc is not the edition's seed: $(grep '^rustc ' /work/build-toolchain.txt)" >&2; exit 1; }; fi
	id builder >/dev/null 2>&1 || useradd --create-home --uid 1000 builder
	;;
build)
	[ -f "/work/source/lc/rustc_$VERSION+lc1.dsc" ] || { echo "run the deps step first" >&2; exit 1; }
	rm -rf /work/tree && cd /work/source/lc
	dpkg-source -x "rustc_$VERSION+lc1.dsc" /work/tree >/dev/null
	chown -R builder:builder /work/tree /work/source
	cd /work/tree
	set +e
	runuser -u builder -- dpkg-buildpackage -us -uc -b -j4 >/work/build.log 2>&1
	status=$?
	set -e
	echo "dpkg-buildpackage: exit $status" | tee /work/build.exit
	if [ "$status" != 0 ] && [ -f debian/sparky-libstd-hash.built ] && [ "$(cat debian/sparky-libstd-hash.built)" != "$(cat debian/sparky-libstd-hash)" ]; then
		cp debian/sparky-libstd-hash.built /work/STD_HASH.found
		echo "the standard library's hash is $(cat /work/STD_HASH.found): record it in $(basename "$VERSION_FILE") and run the repackage step" | tee -a /work/build.exit
	fi
	[ "$status" = 0 ]
	;;
repackage)
	found=$(cat /work/STD_HASH.found)
	make_source "$found" /work/source-final
	# the compiled tree takes the final source's debian/ files; nothing outside debian/ differs between the two sources
	rm -rf /work/final-tree-debian && mkdir /work/final-tree-debian
	tar -C /work/final-tree-debian -xf "/work/source-final/lc/rustc_$VERSION+lc1.debian.tar.xz"
	cd /work/tree
	rm -f debian/libstd-rust-discover.install debian/libstd-rust-discover.triggers debian/libstd-rust-discover.lintian-overrides
	(cd /work/final-tree-debian/debian && find . -type f -print0) | while IFS= read -r -d '' f; do
		if ! cmp -s "/work/final-tree-debian/debian/$f" "debian/$f"; then
			echo "debian/$f: taken from the final source" >>/work/repackage-changed.txt
			install -D -m "$(stat -c %a "/work/final-tree-debian/debian/$f")" "/work/final-tree-debian/debian/$f" "debian/$f"
		fi
	done
	rm -f debian/sparky-libstd-hash.built
	chown -R builder:builder /work/tree /work/source-final
	rm -f /work/*.deb /work/*.changes /work/*.buildinfo
	runuser -u builder -- dpkg-buildpackage -us -uc -b -nc -j4 >/work/build-2.log 2>&1
	echo "dpkg-buildpackage -nc: exit 0" | tee /work/build-2.exit
	;;
*)
	echo "unknown step $STEP" >&2
	exit 2
	;;
esac
