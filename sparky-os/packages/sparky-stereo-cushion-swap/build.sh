#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/10
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/02
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?Set OUT to the workspace output directory}
VERSION=0.3.1
PACKAGE=sparky-stereo-cushion-swap
mkdir -p "$OUT"
WORK=$(mktemp -d "$OUT/.cushion-swap.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
D=$WORK/$PACKAGE
mkdir -p "$D/DEBIAN" "$D/usr/share/doc/$PACKAGE" "$D/usr/libexec/cushion-swap"
gcc ${CFLAGS:--O2 -Wall -Wextra -Werror} -o "$D/usr/libexec/cushion-swap/psi-wake" "$HERE/src/psi-wake.c"
strip --strip-unneeded "$D/usr/libexec/cushion-swap/psi-wake"
gcc ${CFLAGS:--O2 -Wall -Wextra -Werror} -pthread -o "$D/usr/libexec/cushion-swap/alloc-rate" "$HERE/src/alloc-rate.c"
strip --strip-unneeded "$D/usr/libexec/cushion-swap/alloc-rate"
install -Dm644 "$HERE/etc/default/cushion-swap" "$D/etc/default/cushion-swap"
install -Dm755 "$HERE/sbin/cushion-swap" "$D/usr/sbin/cushion-swap"
install -Dm644 -t "$D/usr/lib/systemd/system" "$HERE/lib/systemd/system/cushion-swap.service" \
	"$HERE/lib/systemd/system/cushion-swap-hibernate.service"
install -Dm755 -t "$D/usr/lib/systemd/system-generators" "$HERE/lib/systemd/system-generators/cushion-swap-hibernate-generator"
install -Dm755 -t "$D/usr/lib/systemd/system-sleep" "$HERE/lib/systemd/system-sleep/cushion-swap"
install -Dm644 -t "$D/usr/lib/tmpfiles.d" "$HERE/lib/tmpfiles.d/cushion-swap.conf"
install -Dm755 -t "$D/usr/share/initramfs-tools/hooks" "$HERE/share/initramfs-tools/hooks/cushion-swap-resume-offset"
install -Dm644 -t "$D/etc/logrotate.d" "$HERE/etc/logrotate.d/sparky-stereo-cushion-swap"
# what is wrong, why and what to do, in the nine languages (0.3.1); the edition's one engine keeps each problem and
# its session notifier shows it (ORDER 350), from these messages built word for word into journal catalogs
install -Dm644 -t "$D/usr/share/sparky/$PACKAGE" "$HERE"/lang/*
sparky-stereo-problems catalog $PACKAGE "$HERE/lang" "$D/usr/lib/systemd/catalog" --subject LOCAL16
install -m644 "$HERE/copyright" "$HERE/README.md" "$D/usr/share/doc/$PACKAGE/"
GLIBC=$(objdump -T "$D/usr/libexec/cushion-swap/psi-wake" "$D/usr/libexec/cushion-swap/alloc-rate" | sed -n 's/.*GLIBC_\([0-9.]*\).*/\1/p' | sort -V | tail -n 1)
DEPENDS="bash, libc6 (>= $GLIBC), logrotate, systemd, util-linux, sparky-stereo-problems (>= 0.1.0)"
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
  where present. Pacing uses the idle-measured allocation rate. Problems
  are logged by default, with weekly rotation; cycle logging is optional.
  Hibernate stays offered with the area off, to the device named in
  /etc/initramfs-tools/conf.d/resume.
EOF
printf '%s\n' /etc/default/cushion-swap /etc/logrotate.d/sparky-stereo-cushion-swap >"$D/DEBIAN/conffiles"
echo 'activate-noawait update-initramfs' >"$D/DEBIAN/triggers"
cat >"$D/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
# A step that fails is said with its own error, in the system's language, and the package still configures,
# as debhelper's own autoscripts do for units ("|| true"). Whether the daemon then runs and protects memory is
# checked, never assumed (0.3.1): it says when it could not start, and what keeps it from protecting memory.
say() {
	/usr/sbin/cushion-swap --say "$@" || echo "cushion-swap: $*" >&2
}
step() {
	if out=$("$@" 2>&1); then
		return 0
	else
		rc=$?
	fi
	say LOCAL19 "$*" "$rc" "$(printf '%s\n' "$out" | tail -n 3 | tr '\n' ' ')"
}
if [ "$1" = configure ] || [ "$1" = abort-upgrade ] || [ "$1" = abort-deconfigure ] || [ "$1" = abort-remove ]; then
	# The log folder and file (root:adm, 0750 and 0640) before the unit opens the file.
	if [ -x /usr/bin/systemd-tmpfiles ]; then
		step systemd-tmpfiles --create cushion-swap.conf
	fi
	for unit in cushion-swap.service cushion-swap-hibernate.service; do
		step deb-systemd-helper unmask "$unit"
		if deb-systemd-helper --quiet was-enabled "$unit"; then
			step deb-systemd-helper enable "$unit"
		else
			step deb-systemd-helper update-state "$unit"
		fi
	done
	if [ -d /run/systemd/system ]; then
		step systemctl --system daemon-reload
		since=$(date +%s)
		step deb-systemd-invoke restart cushion-swap.service
		# the person's own switches (CUSHION_SWAP=off, a disabled or masked unit) are said as their choice
		/usr/sbin/cushion-swap --wait-ready "$since" || :
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
# a problem of a package that is gone cannot be repaired by it (ORDER 350): the engine lets go of them
if [ "$1" = remove ] && command -v sparky-stereo-problems >/dev/null; then
	sparky-stereo-problems clear --all sparky-stereo-cushion-swap || :
fi
if [ "$1" = purge ]; then
	rm -rf /var/log/cushion-swap
fi
EOF
chmod 755 "$D/DEBIAN/postinst" "$D/DEBIAN/prerm" "$D/DEBIAN/postrm"
(cd "$D" && find etc usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums)
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

  * Nothing fails silently (ORDER 346b, rows U17, U18 and U54 of ORDER 343's
    audit): whatever keeps the daemon from protecting memory, or from
    protecting it the way it was set, is kept as a problem by the edition's
    one engine, sparky-stereo-problems, for this boot (ORDER 350), named in
    the status (PROTECTION, PROBLEMS, REASON, CALIBRATION, MODE_REASON), said
    once in the journal and shown by the engine's session notifier, in the
    nine languages; the problems go when the package is removed.
  * The package checks that the restarted daemon runs and says whether it
    protects memory; each failed setup step is said with its own error.
  * --status exits 0 only while memory is protected; a stopped, failed or
    unreadable state is never "stopped" with exit 0. The unit's
    ExecStopPost says why the daemon stopped.
  * A kernel with PSI whose trigger is lost, and a failed allocation-rate
    measurement, are said and kept; the poller and the retry a minute
    later go on as before.
  * Hibernation: a failed switch-on, a kernel resume device that differs
    and a failed switch-off after resume fail their unit and are kept.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Mon, 02 Nov 2026 12:00:00 -0300

$PACKAGE (0.3.0) unstable; urgency=medium

  * Measure the machine's allocation rate while idle for headroom pacing.
  * Problems only by default; optional cycle logging and weekly rotation.
  * Fail clearly when the test runner has no logrotate.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Sun, 11 Oct 2026 21:00:00 -0300

$PACKAGE (0.1.0) unstable; urgency=medium

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
