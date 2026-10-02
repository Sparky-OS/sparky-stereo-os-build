#!/bin/bash
# Sets the provenance of our packages the Sparky way (Daniel, 2026-10-02), on .deb files
# already built (the builders get the same identity for their next builds):
#   Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
#   Homepage: https://sparkylinux.org
#   Original-Maintainer: whoever maintained the package we modified (Debian Qt/KDE, NVIDIA),
#                        the Debian-derivative convention
# and signs the latest changelog entry with the same identity when a build container left
# root@<container> there, and credits the edition in each copyright file: Sparky Stereo OS,
# an edition of SparkyLinux, created by Paweł "pavroo" Pijanowski and Daniel Ramos
# (Capitain Jack).
# Usage: provenance.sh file.deb...   (rewrites them in place)
set -euo pipefail
NAME='Daniel Ramos (Capitain Jack)'
MAIL='Capitain_Jack@yahoo.com'
ME="$NAME <$MAIL>"
HOME_URL=https://sparkylinux.org
MARK='Sparky Stereo OS packaging'
PAWEL='Paweł "pavroo" Pijanowski <pavroo@onet.eu>'
# The edition is Daniel's, on Paweł's SparkyLinux: created by both (Daniel, 2026-10-02).
STANZA="Files: debian/*
Comment: $MARK. Sparky Stereo OS, an edition of SparkyLinux ($HOME_URL),
 created by $PAWEL and $ME.
Copyright: 2026 $PAWEL
           2026 $ME
License: GPL-2+
 On Debian systems the full text of the GNU General Public License version 2
 is in /usr/share/common-licenses/GPL-2."
for deb in "$@"; do
	if [ "$(dpkg-deb -f "$deb" Maintainer)" = "$ME" ] && [ "$(dpkg-deb -f "$deb" Homepage)" = "$HOME_URL" ] &&
		dpkg-deb --fsys-tarfile "$deb" | tar -xO --wildcards './usr/share/doc/*/copyright' 2>/dev/null | grep -q -F "created by $PAWEL and $ME."; then
		echo "$(basename "$deb"): already signed"
		continue
	fi
	w=$(mktemp -d /K3D/temp/sparky-os/prov.XXXXXX)
	dpkg-deb -R "$deb" "$w"
	python3 - "$w/DEBIAN/control" "$ME" "$HOME_URL" <<'PY'
import sys, re
path, me, home = sys.argv[1:4]
c = open(path).read()
m = re.search(r'^Maintainer: (.*)$', c, flags=re.M)
old = m.group(1) if m else ''
if old and old != me and not old.startswith('root ') and 'Daniel Campos Ramos' not in old:
    c = re.sub(r'^Original-Maintainer: .*\n', '', c, flags=re.M)
    c = re.sub(r'^Maintainer: .*$', f'Maintainer: {me}\nOriginal-Maintainer: {old}', c, flags=re.M)
else:
    c = re.sub(r'^Maintainer: .*$', f'Maintainer: {me}', c, flags=re.M)
if re.search(r'^Homepage: ', c, flags=re.M):
    c = re.sub(r'^Homepage: .*$', f'Homepage: {home}', c, flags=re.M)
else:
    c = re.sub(r'^(Description: )', f'Homepage: {home}\n\\1', c, count=1, flags=re.M)
open(path, 'w').write(c)
PY
	for cl in "$w"/usr/share/doc/*/changelog.Debian.gz; do
		[ -f "$cl" ] || continue
		[ -L "$cl" ] && continue
		zcat "$cl" | sed -E "0,/^ -- root <root@[^>]*>/s// -- $ME/" | gzip -9n >"$cl.new"
		mv "$cl.new" "$cl"
	done
	# Packaging credit in each copyright file, in Debian's copyright format; an older
	# credit of ours is replaced.
	for cf in "$w"/usr/share/doc/*/copyright; do
		[ -f "$cf" ] && [ ! -L "$cf" ] || continue
		STANZA="$STANZA" MARK="$MARK" python3 - "$cf" <<'PY'
import os, sys
f = sys.argv[1]
t = open(f, encoding='utf-8', errors='surrogateescape').read()
k = t.find('\nFiles: debian/*\nComment: ' + os.environ['MARK'])
if k >= 0:
    t = t[:k]
t = t.rstrip('\n') + '\n\n' + os.environ['STANZA'] + '\n'
open(f, 'w', encoding='utf-8', errors='surrogateescape').write(t)
PY
	done
	# Checksums of every file except the configuration files, as Debian's tools do.
	(cd "$w" && find . -path ./DEBIAN -prune -o -type f -print | sed 's|^\./||' | sort |
		grep -v -x -F -f <(sed 's|^/||' DEBIAN/conffiles 2>/dev/null || true) |
		tr '\n' '\0' | xargs -0 -r md5sum >DEBIAN/md5sums)
	dpkg-deb --root-owner-group -Zxz -b "$w" "$deb" >/dev/null
	rm -rf "$w"
	printf '%s: %s | %s\n' "$(basename "$deb")" "$(dpkg-deb -f "$deb" Maintainer)" "$(dpkg-deb -f "$deb" Original-Maintainer)"
done
