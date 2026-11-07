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
# Daniel Ramos's edition of SparkyLinux (by Paweł "pavroo" Pijanowski), in
# Daniel's wording of 2026-10-07; the Copyright holders stay as they were.
# Usage: provenance.sh file.deb...   (rewrites them in place)
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
NAME='Daniel Ramos (Capitain Jack)'
MAIL='Capitain_Jack@yahoo.com'
ME="$NAME <$MAIL>"
HOME_URL=https://sparkylinux.org
BUGS_URL=https://github.com/Sparky-OS/sparky-stereo-os/issues
MARK='Sparky Stereo OS packaging'
PAWEL='Paweł "pavroo" Pijanowski'
PAWEL_NAME='Paweł "pavroo" Pijanowski'
# The edition is Daniel's, on Paweł's SparkyLinux (Daniel, 2026-10-07).
STANZA="Files: debian/*
Comment: $MARK. Sparky Stereo OS, Daniel Ramos's edition of SparkyLinux (by $PAWEL_NAME).
Copyright: 2026 $PAWEL
           2026 $NAME
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
	# Packaging credit in each copyright file, in Debian's copyright format; an older credit of ours is
	# replaced. DEP-5 gives a file the last Files paragraph that matches it (Debian copyright format 1.0,
	# "Files" field), so ours never sits after a paragraph of Debian's for debian/*: where the package
	# has none, ours names all of debian/*; where it has one, ours names only the files that are ours.
	for cf in "$w"/usr/share/doc/*/copyright; do
		[ -f "$cf" ] && [ ! -L "$cf" ] || continue
		STANZA="$STANZA" MARK="$MARK" PAWEL="$PAWEL" NAME="$NAME" python3 - "$cf" "${SOURCE_ROOT:-}" <<'PY'
import glob, os, re, sys
f, source = sys.argv[1:3]
env = os.environ
t = open(f, encoding='utf-8', errors='surrogateescape').read()
mark = env['MARK']
stanza = env['STANZA']
LEAN = ['debian/sparky-lean-toolkit/*', 'debian/sparky-lean-preserve.json', 'debian/sparky-lean-payload-generated.json']
MANIFEST = 'debian/sparky-provenance-files'


def declared(root):
    # the files of ours that the source tree shows: what Lean Code writes there and what the recipe lists
    found = []
    if not root:
        return ['debian/sparky-lean-toolkit/*']
    for pattern in LEAN:
        if glob.glob(os.path.join(root, pattern)):
            found.append(pattern)
    path = os.path.join(root, MANIFEST)
    if os.path.isfile(path):
        found.append(MANIFEST)
        for line in open(path, encoding='utf-8'):
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            if not re.fullmatch(r'debian/[A-Za-z0-9_.+*?@~=:-]+(?:/[A-Za-z0-9_.+*?@~=:-]+)*', line) or '..' in line.split('/'):
                sys.exit(f'{path}: "{line}" is not a path under debian/ (no spaces, no ..)')
            if not glob.glob(os.path.join(root, line)):
                sys.exit(f'{path}: "{line}" matches no file of the source tree')
            found.append(line)
    return found


def paragraphs(text):
    return [p for p in re.split(r'\n{2,}', text) if p.strip()]


def patterns(paragraph):
    m = re.match(r'Files:((?:[^\n]*)(?:\n[ \t][^\n]*)*)', paragraph)
    return m.group(1).split() if m else None


# our earlier credit: a paragraph that starts with Files and has our Comment as its next field
old = re.search(r'(?:^|\n)(Files:(?:[^\n]*)(?:\n[ \t][^\n]*)*\nComment: ' + re.escape(mark) + r'[^\n]*(?:\n[^\n]+)*)\n*', t)
before_old = []
licence = 'GPL-2+'
if old:
    first = patterns(old.group(1))
    if first and first != ['debian/*']:
        before_old = first
    m = re.search(r'^License: (\S+)$', old.group(1), re.M)
    # a packaging of ours under another licence keeps it (DisplayXR's is BSL-1.0, as agreed with the
    # project); the licence is then a short name whose stand-alone paragraph comes earlier in the file
    if m:
        licence = m.group(1)
    t = (t[:old.start()] + '\n' + t[old.end():]).strip('\n') + '\n'
t = re.sub(r'\n*' + re.escape(mark) + r': [^\n]*(?:\n[^\n]+)*\n*', '\n', t).strip('\n') + '\n'
head = t.lstrip().startswith('Format:')
other = [patterns(p) for p in paragraphs(t)]
debian_taken = any(ps and any(x.startswith('debian/') for x in ps) for ps in other)
credit = stanza.split('\nLicense: ', 1)[0]
if licence != 'GPL-2+':
    credit += '\nLicense: ' + licence
else:
    credit = stanza
t = t.rstrip('\n') + '\n\n'
if head and not debian_taken:
    out = credit
elif head:
    mine = []
    for x in before_old + declared(source):
        if x not in mine:
            mine.append(x)
    files = 'Files: ' + mine[0] + ''.join('\n ' + x for x in mine[1:])
    out = files + credit[credit.index('\n'):]
else:
    # not in Debian's copyright format: no Files or License field, so nothing here overrides what the file says
    out = ('Sparky Stereo OS packaging: Sparky Stereo OS, Daniel Ramos\'s edition of SparkyLinux (by %s).\n'
           'The packaging files this edition added are Copyright 2026 %s and %s, under the GNU General Public License\n'
           'version 2 or later (see /usr/share/common-licenses/GPL-2); the file above keeps the credit for the rest.'
           % (env['PAWEL'], env['PAWEL'], env['NAME']))
t += out + '\n'
open(f, 'w', encoding='utf-8', errors='surrogateescape').write(t)
PY
	done
	# Checksums of every file except the configuration files, as Debian's tools do.
	(cd "$w" && find . -path ./DEBIAN -prune -o -type f -print | sed 's|^\./||' | sort |
		{ grep -v -x -F -f <(sed 's|^/||' DEBIAN/conffiles 2>/dev/null || true) || [ "$?" = 1 ]; } |
		tr '\n' '\0' | xargs -0 -r md5sum >DEBIAN/md5sums)
}
if [ "${1:-}" = --tree ]; then
	SOURCE_ROOT=''
	[ $# = 4 ] && [ "$3" = --source ] && [ -d "$4/debian" ] && SOURCE_ROOT=$4 && set -- "$1" "$2"
	[ $# = 2 ] && [ -f "$2/DEBIAN/control" ] || { echo "usage: provenance.sh --tree STAGING [--source SOURCE_ROOT]" >&2; exit 2; }
	export SOURCE_ROOT
	if grep -qi '^Sparky-Lean-Code:' "$2/DEBIAN/control"; then
		echo "provenance must precede the lc marker; rebuild a fresh staging tree" >&2; exit 1
	fi
	stamp_tree "$2"
	exit 0
fi
for deb in "$@"; do
	if [ "$(dpkg-deb -f "$deb" Maintainer)" = "$ME" ] && [ "$(dpkg-deb -f "$deb" Homepage)" = "$HOME_URL" ] &&
		[ "$(dpkg-deb -f "$deb" Bugs)" = "$BUGS_URL" ] &&
		dpkg-deb --fsys-tarfile "$deb" | tar -xO --wildcards './usr/share/doc/*/copyright' 2>/dev/null | grep -q -F "Daniel Ramos's edition of SparkyLinux"; then
		echo "$(basename "$deb"): already signed"
		continue
	fi
	if [ -n "$(dpkg-deb -f "$deb" Sparky-Lean-Code)" ]; then
		echo "$deb: lc-sealed package needs provenance fixed in a fresh build, before Lean Code" >&2
		exit 1
	fi
	w=$(mktemp -d ${SPARKY_SCRATCH:?}/sparky-os/prov.XXXXXX)
	dpkg-deb -R "$deb" "$w"
	stamp_tree "$w"
	# written beside and renamed over, so that whoever reads the repository at that moment (another lane's build, apt) never
	# sees a half-written package
	dpkg-deb --root-owner-group -Zxz -b "$w" "$deb.stamping" >/dev/null
	mv -f "$deb.stamping" "$deb"
	rm -rf "$w"
	printf '%s: %s | %s\n' "$(basename "$deb")" "$(dpkg-deb -f "$deb" Maintainer)" "$(dpkg-deb -f "$deb" Original-Maintainer)"
done
