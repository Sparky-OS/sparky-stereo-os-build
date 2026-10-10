#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/10
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/10
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?Set OUT to the workspace output directory}
VERSION=0.1.0
PACKAGE=sparky-stereo-cushion-swap
mkdir -p "$OUT"
WORK=$(mktemp -d "$OUT/.cushion-swap.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
D=$WORK/$PACKAGE
mkdir -p "$D/DEBIAN" "$D/usr/share/doc/$PACKAGE" "$D/usr/libexec/cushion-swap"
gcc ${CFLAGS:--O2 -Wall -Wextra -Werror} -o "$D/usr/libexec/cushion-swap/psi-wake" "$HERE/src/psi-wake.c"
strip --strip-unneeded "$D/usr/libexec/cushion-swap/psi-wake"
install -Dm755 "$HERE/sbin/cushion-swap" "$D/usr/sbin/cushion-swap"
install -Dm644 -t "$D/usr/lib/systemd/system" "$HERE/lib/systemd/system/cushion-swap.service" \
	"$HERE/lib/systemd/system/cushion-swap-hibernate.service"
install -Dm755 -t "$D/usr/lib/systemd/system-generators" "$HERE/lib/systemd/system-generators/cushion-swap-hibernate-generator"
install -Dm755 -t "$D/usr/lib/systemd/system-sleep" "$HERE/lib/systemd/system-sleep/cushion-swap"
install -m644 "$HERE/copyright" "$HERE/README.md" "$D/usr/share/doc/$PACKAGE/"
GLIBC=$(objdump -T "$D/usr/libexec/cushion-swap/psi-wake" | sed -n 's/.*GLIBC_\([0-9.]*\).*/\1/p' | sort -V | tail -n 1)
DEPENDS="bash, libc6 (>= $GLIBC), systemd, util-linux"
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOF
Package: $PACKAGE
Version: $VERSION
Architecture: amd64
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: $DEPENDS
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: Cushion Swap File: swap only under memory pressure
  Daniel Ramos's swap parachute. The swap area stays off and is switched on
  when available memory runs low or falls fast, then switched off again only
  when that cannot itself run out of memory. The kernel wakes it through PSI
  where present. Hibernate stays offered with the area off at boot.
EOF
cat >"$D/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = configure ] || [ "$1" = abort-upgrade ] || [ "$1" = abort-deconfigure ] || [ "$1" = abort-remove ]; then
	for unit in cushion-swap.service cushion-swap-hibernate.service; do
		deb-systemd-helper unmask "$unit" >/dev/null || true
		if deb-systemd-helper --quiet was-enabled "$unit"; then
			deb-systemd-helper enable "$unit" >/dev/null || true
		else
			deb-systemd-helper update-state "$unit" >/dev/null || true
		fi
	done
	if [ -d /run/systemd/system ]; then
		systemctl --system daemon-reload >/dev/null || true
		deb-systemd-invoke restart cushion-swap.service >/dev/null || true
	fi
fi
EOF
cat >"$D/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e
# Stopping the daemon never changes the swap state.
if [ -d /run/systemd/system ] && [ "$1" = remove ]; then
	deb-systemd-invoke stop cushion-swap.service >/dev/null || true
fi
EOF
cat >"$D/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
if [ -d /run/systemd/system ]; then
	systemctl --system daemon-reload >/dev/null || true
fi
if [ "$1" = remove ] && [ -x /usr/bin/deb-systemd-helper ]; then
	deb-systemd-helper mask cushion-swap.service cushion-swap-hibernate.service >/dev/null || true
fi
if [ "$1" = purge ] && [ -x /usr/bin/deb-systemd-helper ]; then
	deb-systemd-helper purge cushion-swap.service cushion-swap-hibernate.service >/dev/null || true
	deb-systemd-helper unmask cushion-swap.service cushion-swap-hibernate.service >/dev/null || true
fi
EOF
chmod 755 "$D/DEBIAN/postinst" "$D/DEBIAN/prerm" "$D/DEBIAN/postrm"
(cd "$D" && find usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums)
dpkg-deb --root-owner-group -Zxz -b "$D" "$OUT/${PACKAGE}_${VERSION}_amd64.deb"

S=$WORK/$PACKAGE-$VERSION
mkdir -p "$S/debian"
cp -a "$HERE/." "$S/"
cat >"$S/debian/control" <<EOF
Source: $PACKAGE
Section: System
Priority: optional
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Standards-Version: 4.7.3
Build-Depends: dpkg-dev, gcc, binutils
Rules-Requires-Root: no
Homepage: https://sparkylinux.org

Package: $PACKAGE
Architecture: amd64
Depends: $DEPENDS
Description: Cushion Swap File: swap only under memory pressure
 Daniel Ramos's swap parachute: the swap area stays off until memory runs low.
EOF
cat >"$S/debian/changelog" <<EOF
$PACKAGE ($VERSION) unstable; urgency=medium

  * First release: Daniel Ramos's swap parachute as the Cushion Swap File.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Sat, 10 Oct 2026 18:00:00 -0300
EOF
cp "$HERE/copyright" "$S/debian/copyright"
mkdir -p "$S/debian/source"
echo '3.0 (native)' >"$S/debian/source/format"
cat >"$S/debian/rules" <<'EOF'
#!/usr/bin/make -f
binary:
	OUT=$(CURDIR)/.. bash ./build.sh
	dpkg-distaddfile $$(dpkg-parsechangelog -S Source)_$$(dpkg-parsechangelog -S Version)_amd64.deb System optional
clean:
build:
EOF
chmod +x "$S/debian/rules"
(cd "$WORK" && dpkg-source -b "$S")
cp "$WORK/${PACKAGE}_${VERSION}.dsc" "$WORK/${PACKAGE}_${VERSION}.tar.xz" "$OUT/"
sync
