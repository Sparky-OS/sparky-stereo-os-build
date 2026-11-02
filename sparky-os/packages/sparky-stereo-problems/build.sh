#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# Builds sparky-stereo-problems (ORDER 350): the engine every package of the edition hands its failures to. The core
# is Zig (cgm-zig, Daniel's Zig; ZIG names it, `zig` by default), built twice from the same source: the command and
# the private C library. Then its own message catalogs (with the command just built), the source package, provenance
# and Lean Code's build-tree. Needs zig, libsystemd-dev, dpkg-dev and python3.
# Last update 2026/11/02
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?Set OUT to the workspace output directory}
ZIG=${ZIG:-zig}
PACKAGE=sparky-stereo-problems
VERSION=$(sed -n '2s/^  Version \([^ ]*\) .*/\1/p' "$HERE/CHANGELOG")
MULTIARCH=x86_64-linux-gnu
PRIVATE=usr/lib/$MULTIARCH/$PACKAGE
mkdir -p "$OUT"
WORK=$(mktemp -d "$OUT/.problems.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
D=$WORK/$PACKAGE
mkdir -p "$WORK/bin"
mkdir -p "$D/usr/bin" "$D/$PRIVATE" "$D/usr/include" "$D/usr/lib/$MULTIARCH/pkgconfig" "$D/usr/lib/python3/dist-packages" \
	"$D/usr/lib/systemd/catalog" "$D/usr/lib/systemd/system/service.d" \
	"$D/usr/lib/systemd/system/sparky-stereo-problems-failed@.service.d" "$D/usr/lib/tmpfiles.d" \
	"$D/usr/share/polkit-1/actions" "$D/usr/share/doc/$PACKAGE"
JOBS=${JOBS:-4}
(cd "$HERE/src" && "$ZIG" build-exe main.zig -lc -lsystemd -O ReleaseSafe -j"$JOBS" \
	--name $PACKAGE -femit-bin="$WORK/bin/$PACKAGE") 2>&1 | grep -v '^info: threads' || :
(cd "$HERE/src" && "$ZIG" build-lib -dynamic capi.zig -lc -lsystemd -O ReleaseSafe -j"$JOBS" \
	--name $PACKAGE -fsoname=lib$PACKAGE.so.0 -femit-bin="$WORK/bin/lib$PACKAGE.so.0") 2>&1 | grep -v '^info: threads' || :
[ -x "$WORK/bin/$PACKAGE" ] && [ -f "$WORK/bin/lib$PACKAGE.so.0" ] || { echo "the Zig build failed" >&2; exit 1; }
install -m 755 "$WORK/bin/$PACKAGE" "$D/usr/bin/$PACKAGE"
install -m 644 "$WORK/bin/lib$PACKAGE.so.0" "$D/$PRIVATE/lib$PACKAGE.so.0"
ln -s lib$PACKAGE.so.0 "$D/$PRIVATE/lib$PACKAGE.so"
strip --strip-unneeded "$D/usr/bin/$PACKAGE" "$D/$PRIVATE/lib$PACKAGE.so.0"
install -m 644 "$HERE/include/$PACKAGE.h" "$D/usr/include/$PACKAGE.h"
cat >"$D/usr/lib/$MULTIARCH/pkgconfig/$PACKAGE.pc" <<EOS
prefix=/usr
libdir=\${prefix}/lib/$MULTIARCH/$PACKAGE
includedir=\${prefix}/include

Name: $PACKAGE
Description: The edition's engine that keeps what failed until it is repaired
Version: $VERSION
Libs: -L\${libdir} -Wl,-rpath,\${libdir} -l$PACKAGE
Cflags: -I\${includedir}
EOS
install -m 644 "$HERE/python/sparky_stereo_problems.py" "$D/usr/lib/python3/dist-packages/sparky_stereo_problems.py"
# the engine's own messages, built by the engine just built, as every package's are (README.md)
"$WORK/bin/$PACKAGE" catalog $PACKAGE "$HERE/lang" "$D/usr/lib/systemd/catalog" \
	--subject LOCAL29 --subject LOCAL1=LOCAL4 --subject LOCAL2=LOCAL13,LOCAL21,LOCAL59 --subject LOCAL3=LOCAL15
install -m 644 "$HERE/systemd/system/service.d/50-sparky-stereo-problems.conf" "$D/usr/lib/systemd/system/service.d/"
install -m 644 "$HERE/systemd/system/sparky-stereo-problems-failed@.service" "$D/usr/lib/systemd/system/"
# the handler's own instances: the top-level drop-in masked, so a handler that fails starts no other (systemd.unit(5))
ln -s /dev/null "$D/usr/lib/systemd/system/sparky-stereo-problems-failed@.service.d/50-sparky-stereo-problems.conf"
install -m 644 "$HERE/tmpfiles/$PACKAGE.conf" "$D/usr/lib/tmpfiles.d/$PACKAGE.conf"
install -m 644 "$HERE/polkit/org.sparkylinux.sparkystereo.problems.policy" "$D/usr/share/polkit-1/actions/"
install -m 644 "$HERE/copyright" "$D/usr/share/doc/$PACKAGE/copyright"
install -m 644 "$HERE/README.md" "$D/usr/share/doc/$PACKAGE/README.md"
mkdir -p "$D/DEBIAN" "$WORK/shlibs/debian"
printf 'Source: %s\n\nPackage: %s\nArchitecture: amd64\n' "$PACKAGE" "$PACKAGE" >"$WORK/shlibs/debian/control"
SHLIBS=$(cd "$WORK/shlibs" && dpkg-shlibdeps -O "$D/usr/bin/$PACKAGE" "$D/$PRIVATE/lib$PACKAGE.so.0" 2>/dev/null | sed -n 's/^shlibs:Depends=//p')
[ -n "$SHLIBS" ] || { echo "dpkg-shlibdeps found no dependencies" >&2; exit 1; }
DEPENDS="$SHLIBS, systemd"
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOS
Package: $PACKAGE
Version: $VERSION
Architecture: amd64
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: $DEPENDS
Suggests: sparky-stereo-problems-plasma, pkexec
Section: admin
Priority: optional
Homepage: https://sparkylinux.org
Description: what failed on the system, kept until it is repaired
  One engine for every package of the Sparky Stereo OS edition: a step that
  cannot do what it is for says what failed, why and what to do, in the
  person's language, and the problem stays kept with its evidence until it is
  repaired; the system journal has it too, explained by journalctl -x. Every
  failed system service is told, with its own last lines and systemd's restart
  as the repair. A command (sparky-stereo-problems), a C library and a Python
  module; sparky-stereo-problems-plasma shows each problem in the session.
EOS
# the stores (systemd-tmpfiles) and the failed-service drop-in (systemd's reload): each failure is said and kept by
# the engine itself, and the package configures, as debhelper's own unit handling does; repair runs it again
cat >"$D/DEBIAN/postinst" <<'EOS'
#!/bin/sh
# postinst script
set -e
if [ "$1" = "configure" ]; then
	if [ -d /run/systemd/system ]; then
		sparky-stereo-problems run --machine sparky-stereo-problems tmpfiles LOCAL34 @LOCAL35 -- systemd-tmpfiles --create sparky-stereo-problems.conf || :
		sparky-stereo-problems run --machine sparky-stereo-problems systemd-reload LOCAL34 @LOCAL36 -- systemctl daemon-reload || :
	else
		mkdir -p /var/lib/sparky-stereo-problems
	fi
fi
exit 0
EOS
cat >"$D/DEBIAN/postrm" <<'EOS'
#!/bin/sh
# postrm script
set -e
if [ "$1" = "remove" ] && [ -d /run/systemd/system ]; then
	systemctl daemon-reload || echo "sparky-stereo-problems: systemctl daemon-reload failed; failed services still name the removed handler until the next reload" >&2
fi
if [ "$1" = "purge" ]; then
	rm -rf /var/lib/sparky-stereo-problems /run/sparky-stereo-problems
fi
exit 0
EOS
chmod 755 "$D/DEBIAN/postinst" "$D/DEBIAN/postrm"
(cd "$D" && find usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums)

S=$WORK/$PACKAGE-$VERSION
mkdir -p "$S/debian/source"
cp -a "$HERE/." "$S/"
cat >"$S/debian/control" <<EOS
Source: $PACKAGE
Section: admin
Priority: optional
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Standards-Version: 4.7.3
Build-Depends: cgm-zig, libsystemd-dev, dpkg-dev, python3
Rules-Requires-Root: no
Homepage: https://sparkylinux.org

Package: $PACKAGE
Architecture: amd64
Depends: \${shlibs:Depends}, systemd
Suggests: sparky-stereo-problems-plasma, pkexec
Description: what failed on the system, kept until it is repaired
 One engine for every package of the edition: what failed, why and what to do,
 kept until it is repaired, in the journal and in the person's session.
EOS
{
	printf '%s (%s) unstable; urgency=medium\n\n' "$PACKAGE" "$VERSION"
	sed -n '4,/^---/p' "$HERE/CHANGELOG" | grep -v '^---' | sed 's/^  \*/  */'
	printf '\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Mon, 02 Nov 2026 12:00:00 -0300\n'
} >"$S/debian/changelog"
cp "$HERE/copyright" "$S/debian/copyright"
echo '3.0 (native)' >"$S/debian/source/format"
cat >"$S/debian/rules" <<'EOS'
#!/usr/bin/make -f
binary:
	OUT=$(CURDIR)/.. bash ./build.sh
	dpkg-distaddfile $$(dpkg-parsechangelog -S Source)_$$(dpkg-parsechangelog -S Version)_amd64.deb admin optional
clean:
build:
EOS
chmod +x "$S/debian/rules"
(cd "$WORK" && dpkg-source -b "$S" >/dev/null)
cp "$WORK/${PACKAGE}_${VERSION}.dsc" "$WORK/${PACKAGE}_${VERSION}.tar.xz" "$OUT/"

"$HERE/../../repo/provenance.sh" --tree "$D"
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.release build-tree "$D" "$OUT"
sync
