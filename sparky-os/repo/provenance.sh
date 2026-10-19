#!/bin/bash
# Sets the provenance of our packages the Sparky way (Daniel, 2026-10-02), on .deb files
# already built (the builders get the same identity for their next builds):
#   Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
#   Homepage: https://sparkylinux.org
#   Bugs: https://github.com/Sparky-OS/sparky-stereo-os/issues   (the edition's tracker: a problem in our build
#         never goes to the maintainer of the package we modified; Daniel, 2026-10-08)
#   Original-Maintainer: whoever maintained the package we modified (Debian Qt/KDE, NVIDIA),
#                        the Debian-derivative convention
# and signs the latest changelog entry with the same identity when a build container left
# root@<container> there, and credits the edition in each copyright file: Sparky Stereo OS,
# Daniel Ramos's (Capitain Jack) edition of SparkyLinux (by Paweł "pavroo" Pijanowski), in
# Daniel's wording of 2026-10-07; the Copyright holders stay as they were.
# Usage: provenance.sh file.deb...   (rewrites them in place)
set -euo pipefail
NAME='Daniel Ramos (Capitain Jack)'
MAIL='Capitain_Jack@yahoo.com'
ME="$NAME <$MAIL>"
HOME_URL=https://sparkylinux.org
BUGS_URL=https://github.com/Sparky-OS/sparky-stereo-os/issues
MARK='Sparky Stereo OS packaging'
PAWEL='Paweł "pavroo" Pijanowski <pavroo@onet.eu>'
PAWEL_NAME='Paweł "pavroo" Pijanowski'
# The edition is Daniel's, on Paweł's SparkyLinux (Daniel, 2026-10-07).
STANZA="Files: debian/*
Comment: $MARK. Sparky Stereo OS, Daniel Ramos's (Capitain Jack) edition of SparkyLinux
 ($HOME_URL, by $PAWEL_NAME).
Copyright: 2026 $PAWEL
           2026 $ME
License: GPL-2+
 On Debian systems the full text of the GNU General Public License version 2
 is in /usr/share/common-licenses/GPL-2."
# Staging mode runs before LC checksums and the marker are finalized.
stamp_tree() {
	local w=$1
	python3 - "$w/DEBIAN/control" "$ME" "$HOME_URL" "$BUGS_URL" <<'PY'
import sys, re
path, me, home, bugs = sys.argv[1:5]
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
# the edition's tracker, whatever the package named before (deb-multimedia's source says its maintainer's e-mail)
if re.search(r'^Bugs: ', c, flags=re.M):
    c = re.sub(r'^Bugs: .*$', f'Bugs: {bugs}', c, flags=re.M)
else:
    c = re.sub(r'^(Homepage: .*)$', f'\\1\nBugs: {bugs}', c, count=1, flags=re.M)
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
}
if [ "${1:-}" = --tree ]; then
	[ $# = 2 ] && [ -f "$2/DEBIAN/control" ] || { echo "usage: provenance.sh --tree STAGING" >&2; exit 2; }
	if grep -qi '^Sparky-Lean-Code:' "$2/DEBIAN/control"; then
		echo "provenance must precede the lc marker; rebuild a fresh staging tree" >&2; exit 1
	fi
	stamp_tree "$2"
	exit 0
fi
for deb in "$@"; do
	if [ "$(dpkg-deb -f "$deb" Maintainer)" = "$ME" ] && [ "$(dpkg-deb -f "$deb" Homepage)" = "$HOME_URL" ] &&
		[ "$(dpkg-deb -f "$deb" Bugs)" = "$BUGS_URL" ] &&
		dpkg-deb --fsys-tarfile "$deb" | tar -xO --wildcards './usr/share/doc/*/copyright' 2>/dev/null | grep -q -F "Daniel Ramos's (Capitain Jack) edition of SparkyLinux"; then
		echo "$(basename "$deb"): already signed"
		continue
	fi
	if [ -n "$(dpkg-deb -f "$deb" Sparky-Lean-Code)" ]; then
		echo "$deb: lc-sealed package needs provenance fixed in a fresh build, before Lean Code" >&2
		exit 1
	fi
	w=$(mktemp -d /K3D/temp/sparky-os/prov.XXXXXX)
	dpkg-deb -R "$deb" "$w"
	stamp_tree "$w"
	# written beside and renamed over, so that whoever reads the repository at that moment (another lane's build, apt) never
	# sees a half-written package
	dpkg-deb --root-owner-group -Zxz -b "$w" "$deb.stamping" >/dev/null
	mv -f "$deb.stamping" "$deb"
	rm -rf "$w"
	printf '%s: %s | %s\n' "$(basename "$deb")" "$(dpkg-deb -f "$deb" Maintainer)" "$(dpkg-deb -f "$deb" Original-Maintainer)"
done
