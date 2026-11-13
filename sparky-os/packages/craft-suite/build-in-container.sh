#!/bin/bash
# Sparky Stereo OS: the Craft suite as one source package, built with the edition's own rustc through Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/11/13
# Copyright 2026 under the GNU GPL3 License
# Runs as root inside a clean Debian testing build container; build.sh starts it. /work is the job folder, /src the
# folder fetch.sh made, /toolkit the build tree's sparky-os folder, /tools this folder, /seed the folder with the
# edition's compiler packages. Steps: deps (the compiler, the source packages and the build dependencies, with the
# network for apt only), source (the source packages alone), build (dpkg-buildpackage, without network), check.
# Last update 2026/11/13
trap 'chown -R 1000:1000 /work/ 2>/dev/null || true' EXIT
set -euo pipefail
: "${SOURCE_DATE_EPOCH:?a source is dated by its recipe, never by the clock: run this through build.sh (sparky_provenance_init)}" "${SOURCE_DATE_RFC2822:?see SOURCE_DATE_EPOCH}"
: "${STEP:?deps, source, build or check}"
j() { python3 -c 'import json,sys; d=json.load(open("/tools/suite.json"))
for k in sys.argv[1:]: d=d[k]
print(d)' "$@"; }
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS="parallel=4"
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com LC_ALL=C.UTF-8
PRESERVE=(
	--preserve-source 'fonts/*' "the font repository's own tools: not compiled in this build, kept as their authors ship them"
	--preserve-source 'i18n/*' "the catalogue repository's own tools: not compiled in this build, kept as their authors ship them"
)

make_source() {    # make_source OUT: OUT/s1 gets the +stereo3dN source, OUT/lc the +stereo3dN+lc1 source
	local out=$1 up version rustc t
	up=$(j release); version=$up-1+$(j edition); rustc=$(j rustc)
	[ "$(dpkg-query -W -f '${Version}' rustc)" = "$rustc" ] || { echo "the installed rustc is $(dpkg-query -W -f '${Version}' rustc), suite.json names $rustc" >&2; exit 1; }
	rm -rf "$out" && mkdir -p "$out/s1" "$out/lc"
	t=$out/s1/craft-suite-$up
	mkdir -p "$t"
	cp -a /src/apps /src/vendor /src/fonts /src/i18n "$t/"
	find "$t" -print0 | xargs -0 touch -h -d "@$SOURCE_DATE_EPOCH"
	(cd "$out/s1" && tar --sort=name --owner=0 --group=0 --numeric-owner --mtime="@$SOURCE_DATE_EPOCH" -cf - "craft-suite-$up" | xz -T1 -2 >"craft-suite_$up.orig.tar.xz")
	mkdir -p "$t/debian"
	cp -a /tools/debian/. "$t/debian/"
	cp -a /tools/suite.json /tools/suite-tree.py /tools/suite-source.py /tools/suite-trees.sh /tools/suite-generate.sh /tools/suite-build.sh /tools/suite-fixups.json "$t/debian/"
	cp -a /src/authors "$t/debian/authors"
	# the libraries' names and the pinned resolve, made with the compiler the build will use
	rm -rf /work/names && install -d -o builder -g builder /work/names
	chown -R builder:builder "$out"
	runuser -u builder -- env HOME=/work/names CARGO_HOME=/work/names/cargo SUITE_TOOLS="$t/debian" SUITE_LOCK=make \
		bash "$t/debian/suite-generate.sh" "$t" /work/names/ws >/work/names.log 2>&1 || { tail -30 /work/names.log >&2; exit 1; }
	cp /work/names/ws/Cargo.lock "$t/debian/suite-Cargo.lock"
	python3 /tools/suite-debian.py "$t" /work/names/ws "$version" "$SOURCE_DATE_RFC2822" "$rustc" "$(j std_package)"
	rm -rf /work/names/ws /work/names/cargo
	python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" "$t"
	(cd "$out/s1" && dpkg-source -b "craft-suite-$up" >/dev/null)
	rm -rf "$t"
	cd "$out/lc"
	cp "../s1/craft-suite_$version.dsc" "../s1/craft-suite_$version.debian.tar.xz" "../s1/craft-suite_$up.orig.tar.xz" .
	dpkg-source -x "craft-suite_$version.dsc" authored >/dev/null
	echo '["c", "rust"]' >authored/debian/sparky-lean-languages.json
	PYTHONPATH=/toolkit python3 -m lean.debian_prepare authored "$version+lc1" --toolkit /toolkit "${PRESERVE[@]}"
	# the vendored crates' checksum manifests go back to their authored bytes before the projection report is removed
	sed -i 's|^\trm -rf \.sparky-lc$|\tpython3 debian/cargo-checksums.py restore\n\trm -rf .sparky-lc|' authored/debian/rules
	grep -q 'cargo-checksums.py restore' authored/debian/rules
	python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" authored
	(cd authored && dpkg-source -b . >/dev/null)
	rm -rf authored
	(cd "$out" && sha256sum s1/*.dsc s1/*.debian.tar.xz s1/*.orig.tar.xz lc/*+lc1.dsc lc/*+lc1.debian.tar.xz) | tee "$out/SOURCE-SHA256SUMS"
}

version() { up=$(j release); VERSION=$up-1+$(j edition); }    # python3 arrives with the deps step's first install
[ "$STEP" = deps ] || version
case $STEP in
deps)    # needs the network for apt; the driver commits the result as the image the build runs in, without network
	apt-get -y update >/work/apt-update.log 2>&1
	apt-get -y --no-install-recommends install devscripts dpkg-dev python3 patch xz-utils >/work/bootstrap.log 2>&1
	version
	[ -d /seed ] || { echo "the edition's compiler packages are needed (SEED_DIR): the suite is built with our rustc only" >&2; exit 1; }
	mkdir -p /var/local/seed && cp /seed/*.deb /var/local/seed/
	(cd /var/local/seed && dpkg-scanpackages --multiversion . >Packages 2>/dev/null)
	echo 'deb [trusted=yes] file:/var/local/seed ./' >/etc/apt/sources.list.d/sparky-seed.list
	printf 'Package: *\nPin: origin ""\nPin-Priority: 1001\n' >/etc/apt/preferences.d/sparky-seed
	apt-get -y update >>/work/apt-update.log 2>&1
	seed=$(apt-cache policy rustc | awk '/Candidate:/ {print $2}')
	[ "$seed" = "$(j rustc)" ] || { echo "apt offers rustc $seed, suite.json names $(j rustc): refusing to build with another compiler" >&2; exit 1; }
	apt-get -y --no-install-recommends install rustc cargo libstd-rust-dev >/work/rust-install.log 2>&1
	id builder >/dev/null 2>&1 || useradd --create-home --uid 1000 builder
	make_source /work/source
	apt-get -y --no-install-recommends build-dep "/work/source/lc/craft-suite_$VERSION+lc1.dsc" >/work/build-dep.log 2>&1
	dpkg-query -W -f '${Package} ${Version}\n' rustc cargo libstd-rust-dev "$(j std_package)" gcc cmake nasm python3 debhelper dpkg-dev >/work/build-toolchain.txt
	;;
source)
	make_source /work/source
	;;
build)
	[ -f "/work/source/lc/craft-suite_$VERSION+lc1.dsc" ] || { echo "run the deps step first" >&2; exit 1; }
	rm -rf /work/tree /work/home && install -d -o builder -g builder /work/home && cd /work/source/lc
	dpkg-source -x "craft-suite_$VERSION+lc1.dsc" /work/tree >/dev/null
	chown -R builder:builder /work/tree /work/source
	cd /work/tree
	set +e
	runuser -u builder -- env HOME=/work/home dpkg-buildpackage -us -uc -b -j4 >/work/build.log 2>&1
	status=$?
	set -e
	echo "dpkg-buildpackage: exit $status" | tee /work/build.exit
	[ "$status" = 0 ]
	;;
check)   # the release gate on the finished archives; writes the build record beside them
	cd /work
	PYTHONPATH=/toolkit python3 -m lean.release check-debs ./*+lc1_*.deb
	;;
*)
	echo "unknown step $STEP" >&2
	exit 2
	;;
esac
