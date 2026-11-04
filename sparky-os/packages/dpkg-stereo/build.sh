#!/bin/bash
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/16
# Copyright 2026 under the MIT License
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
# Builds dpkg-stereo: Lean Code for installed packages (sparky-os/LEAN-CODE-POLICY.md, "Install-time
# projection: dpkg-stereo"). It carries the lean package (sparky-os/lean, the MR/HR compiler ported from
# CGM) in /usr/lib/dpkg-stereo, dpkg's pre-invoke and post-invoke hooks, the first-update hook that writes
# the HR copies of settings, and the pre-squashfs hook Sparky Backup Core Stereo runs for the ISO.
# Needs only dpkg-deb; run it in a throwaway container or on any Debian.
# Last update 2026/11/03
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
umask 022
HERE=$(cd "$(dirname "$0")" && pwd)
LEAN=$(cd "$HERE/../../lean" && pwd)
OUT=${OUT:-${SPARKY_REPO_DIR:?}}
VERSION=0.1.35
PKG=dpkg-stereo
W=$(mktemp -d "${TMPDIR:-/tmp}/dpkg-stereo-build.XXXXXX")
trap 'rm -rf "$W"' EXIT
COPY="$HERE/../../../tools/copy-recipe.py"
python3 "$COPY" "$LEAN" "$W/lean-inputs"
LEAN=$W/lean-inputs
D=$W/$PKG
mkdir -p "$D/DEBIAN" "$D/usr/sbin" "$D/usr/lib/dpkg-stereo/lean" "$D/etc/dpkg/dpkg.cfg.d" "$D/etc/apt/apt.conf.d" \
	"$D/usr/share/doc/$PKG" "$D/usr/share/sparky/$PKG" "$D/usr/lib/systemd/catalog"
# the program is a module beside the lean toolkit, so Python reads its byte-compiled form at every start instead of
# compiling it again (a script is compiled at every run: about 28 ms of each dpkg hook, ORDER 367); the command loads it
install -m 644 "$HERE/bin/dpkg-stereo" "$D/usr/lib/dpkg-stereo/dpkg_stereo.py"
cat >"$D/usr/sbin/dpkg-stereo" <<'EOS'
#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
# dpkg-stereo: the program is /usr/lib/dpkg-stereo/dpkg_stereo.py, whose byte-compiled form Python reads at every
# start; its names are this file's too, for a caller that loads this file as a module
import os
import sys
sys.path.insert(0, os.environ.get('DPKG_STEREO_LIB', '/usr/lib/dpkg-stereo'))
from dpkg_stereo import *  # noqa: F401,F403
from dpkg_stereo import main
if __name__ == '__main__':
    sys.exit(main())
EOS
chmod 755 "$D/usr/sbin/dpkg-stereo"
install -m 755 "$HERE/lib/presquashfs-hook" "$D/usr/lib/dpkg-stereo/presquashfs-hook"
install -m 644 "$HERE/lib/conffile_events.py" "$D/usr/lib/dpkg-stereo/conffile_events.py"
install -m 755 "$HERE/lib/conffile-verify" "$D/usr/lib/dpkg-stereo/conffile-verify"
install -m 644 "$LEAN"/*.py "$LEAN/JvmLexer.java" "$LEAN/ZigTokens.zig" "$D/usr/lib/dpkg-stereo/lean/"
install -m 644 "$HERE/etc/dpkg-stereo.cfg" "$D/etc/dpkg/dpkg.cfg.d/dpkg-stereo"
install -m 644 "$HERE/etc/99dpkg-stereo-hr" "$D/etc/apt/apt.conf.d/99dpkg-stereo-hr"
install -m 644 "$HERE/copyright" "$D/usr/share/doc/$PKG/copyright"
# what failed, why and what to do, in the nine languages (0.1.25); the edition's one engine keeps a problem and its
# session notifier shows it (ORDER 350), from these messages built word for word into journal catalogs
python3 "$COPY" "$HERE/lang" "$W/lang-inputs"
install -m 644 "$W/lang-inputs"/* "$D/usr/share/sparky/$PKG/"
sparky-stereo-problems catalog $PKG "$D/usr/share/sparky/$PKG" "$D/usr/lib/systemd/catalog" --subject LOCAL16
printf '/etc/apt/apt.conf.d/99dpkg-stereo-hr\n/etc/dpkg/dpkg.cfg.d/dpkg-stereo\n' >"$D/DEBIAN/conffiles"
cat >"$D/DEBIAN/postinst" <<'EOS'
#!/bin/sh
# postinst script
set -e
# Lean Code never fails dpkg-stereo's own configuration: a step that does not complete is said by dpkg-stereo
# itself (what, why, what to do), kept by the edition's one engine and repaired with dpkg-stereo --repair;
# every file stays its package's original or a checked projection
# the program and the lean toolkit byte-compiled now, as Debian's Python packages are (py3compile, removed by the
# prerm's py3clean), so no dpkg hook compiles them
if [ "$1" = "configure" ] && command -v py3compile >/dev/null 2>&1; then
	py3compile -p dpkg-stereo /usr/lib/dpkg-stereo || true
fi
if [ "$1" = "configure" ] && [ -z "${DPKG_STEREO_NO_PROJECT:-}" ]; then
	/usr/sbin/dpkg-stereo --repair-consumers --if-changed || true
	# dpkg read its hooks before this run, and this package's hook file is a conffile that arrives only now,
	# so the first projection of the installed packages is made here; an upgrade finds them recorded already,
	# and its own post-invoke run takes only what it changed
	if [ -z "${2:-}" ] || [ ! -e /var/lib/dpkg-stereo/packages.tsv ]; then
		/usr/sbin/dpkg-stereo --project || true
		# what this dpkg run configures after this package is projected when dpkg processes this trigger,
		# at the end of its run (deb-triggers(5), interest-noawait)
		dpkg-trigger --no-await dpkg-stereo-first-projection || true
	fi
fi
if [ "$1" = "triggered" ] && [ -z "${DPKG_STEREO_NO_PROJECT:-}" ]; then
	/usr/sbin/dpkg-stereo --post-invoke || true
fi
exit 0
EOS
printf 'interest-noawait dpkg-stereo-first-projection\n' >"$D/DEBIAN/triggers"
cat >"$D/DEBIAN/prerm" <<'EOS'
#!/bin/sh
# prerm script
set -e
if [ "$1" = "remove" ]; then
	# the way back: the original files return (conffiles from the record, other files from their packages' .deb,
	# fetched from snapshot.debian.org when no cache or source has the installed version); what cannot come back is
	# said with its reason and what brings it back once dpkg-stereo is gone, and the removal goes on (a failing
	# prerm would keep dpkg-stereo installed, Debian Policy 6.6)
	/usr/sbin/dpkg-stereo --restore || true
	# without the package table a later install projects everything again
	rm -f /var/lib/dpkg-stereo/packages.tsv
fi
# the byte-compiled files the postinst (or a run) made, last, after the program's own last run
if command -v py3clean >/dev/null 2>&1; then
	py3clean -p dpkg-stereo || true
fi
exit 0
EOS
cat >"$D/DEBIAN/postrm" <<'EOS'
#!/bin/sh
# postrm script
set -e
# a problem of a package that is gone cannot be repaired by it (ORDER 350): the engine lets go of them
if [ "$1" = "remove" ] && command -v sparky-stereo-problems >/dev/null; then
	sparky-stereo-problems clear --all dpkg-stereo || :
fi
if [ "$1" = "purge" ]; then
	rm -rf /var/lib/dpkg-stereo
fi
exit 0
EOS
chmod 755 "$D/DEBIAN/postinst" "$D/DEBIAN/prerm" "$D/DEBIAN/postrm"
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOS
Package: $PKG
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Pre-Depends: dpkg (>= 1.23.11+stereo3d1+lc1), dpkg-lean-code (>= 1)
Depends: python3, apt, sparky-stereo-problems (>= 0.1.0)
Recommends: gcc, node-acorn, nodejs, perl, python3-yaml
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: Lean Code for installed packages
  Sparky Stereo OS keeps the packages of every source as they were built and
  projects the text files they install (scripts, QML and JavaScript, settings,
  units and rules, headers) into their machine form, without the comments the
  machine never reads. Each projection is checked by the file's own reader,
  recorded and reversible; settings edited by the person are never touched,
  and dpkg never asks about a projected setting.
EOS
(cd "$D" && find . -path ./DEBIAN -prune -o -type f -print | sed 's|^\./||' | grep -v '^etc/' | sort | xargs md5sum) >"$D/DEBIAN/md5sums"
mkdir -p "$OUT"
"$HERE/../../repo/provenance.sh" --tree "$D"
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.release build-tree "$D" "$OUT"
