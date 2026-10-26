#!/bin/bash
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/05
# Copyright 2026 under the GNU GPL3 License
# Turns the flat development repository (make-repo.sh) into the public, signed apt tree of
# Sparky Stereo OS 9 "Mashtabba" (Debian 14 "Forky"), in the standard Debian layout:
#   pool/main/<first letter or libX>/<source name>/*.deb
#   dists/mashtabba/Release, InRelease, Release.gpg
#   dists/mashtabba/main/binary-amd64/Packages{,.gz,.xz}   (Architecture: amd64)
#   dists/mashtabba/main/binary-i386/Packages{,.gz,.xz}    (Architecture: i386, when there are i386 packages)
#   dists/mashtabba/main/binary-arm64/Packages{,.gz,.xz}   (Architecture: arm64, when there are arm64 packages)
#   dists/mashtabba/main/binary-all/Packages{,.gz,.xz}     (Architecture: all, as apt asks for them)
#   dists/mashtabba/main/source/Sources{,.gz,.xz}          (only when source packages are given)
#   dists/mashtabba/main/Contents-<arch>{,.gz,.xz}         (amd64 always; i386, arm64 and all when selected; every file of every
#                                                           selected binary package, Architecture: all included in each architecture's
#                                                           file, as Debian's archive does; what apt-file and command-not-found read)
# SparkyLinux's shape with our names: Origin and Label are the distribution ("Sparky Stereo
# OS"), the Codename is the version of the edition (mashtabba, tied to a Debian: a new
# Debian means a new codename of the same edition) and the Suite is its role (testing; it
# becomes stable when the next codename starts). The directory is dists/<codename>.
#   .../by-hash/SHA256/<hash>   (Acquire-By-Hash: yes; the last days' files are kept for
#                                clients that are in the middle of an update)
#   index.html, sparky-stereo-repo.asc (the public key, armoured, exported here)
# Only the newest version of each package (per architecture) goes into the tree; the older
# ones left out are listed. Source packages (.dsc and the files it names) are taken from
# $SPARKY_REPO_SOURCES (default SRC/source, if it exists) when the .dsc version is the version
# the binary was built from; the sources index exists only if at least one matches, and the
# source names without a match are listed (publishing sources is then partial). SRC (also its carried/ folder) is only read, never written.
# Safe to run again: unchanged pool files are kept, files of versions that are no longer the
# newest are removed from the pool, and when nothing changed the signed Release stays as it was.
#
# Usage: SPARKY_REPO_KEY=<fingerprint> SPARKY_REPO_GNUPGHOME=<gnupg home> \
#        publish-tree.sh SRC DEST [extra.deb ...]
#   extra.deb: more packages to include (for example the sparky-stereo-keyring package).
# With a key that has a passphrase, gpg-agent asks for it once (run from a terminal); it
# stays cached for the run. A key without a passphrase signs without asking.
# Last update 2026/10/24 (Contents files, ORDER 251)
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
CODENAME=mashtabba
SUITE=testing
ORIGIN="Sparky Stereo OS"
COMPONENT=main
EDITION_VERSION=9
DESCRIPTION="Sparky Stereo OS testing repository"
KEEP_BYHASH_DAYS=3

[ $# -ge 2 ] || { sed -n '/^# Usage/,/^# Last/p' "$0" | sed 's/^# \?//' >&2; exit 2; }
SRC=$(cd "$1" && pwd)
mkdir -p "$2"
DEST=$(cd "$2" && pwd)
shift 2
EXTRA=("$@")
: "${SPARKY_REPO_KEY:?set SPARKY_REPO_KEY to the signing key fingerprint}"
: "${SPARKY_REPO_GNUPGHOME:?set SPARKY_REPO_GNUPGHOME to the GnuPG home that holds the key}"
[ -n "$DEST" ] && [ "$DEST" != / ] || { echo "bad DEST" >&2; exit 2; }
[ "$SRC" != "$DEST" ] || { echo "SRC and DEST must differ" >&2; exit 2; }
case "$DEST/" in "$SRC"/*) echo "DEST must not be inside SRC" >&2; exit 2 ;; esac
GPG=(gpg --homedir "$SPARKY_REPO_GNUPGHOME" --batch --yes)
GPG_TTY=$(tty 2>/dev/null || true)
export GPG_TTY
"${GPG[@]}" --list-secret-keys "$SPARKY_REPO_KEY" >/dev/null 2>&1 || {
	echo "no secret key $SPARKY_REPO_KEY in $SPARKY_REPO_GNUPGHOME" >&2
	exit 1
}
FPR=$(gpg --homedir "$SPARKY_REPO_GNUPGHOME" --with-colons --fingerprint "$SPARKY_REPO_KEY" |
	awk -F: '/^fpr:/ {print $10; exit}')
umask 022

W=$(mktemp -d "${TMPDIR:-${SPARKY_SCRATCH:?}}/publish-tree.XXXXXX")
trap 'rm -rf "${W:?}"' EXIT

# 1. Choose the newest version of each package and where it goes in the pool.
SOURCES_DIR=${SPARKY_REPO_SOURCES:-$SRC/source}
export SOURCES_DIR
python3 - "$SRC" "$W/selection.tsv" "$W/leftout.txt" "${EXTRA[@]}" <<'PY'
import hashlib, os, sys, subprocess

src, out_sel, out_left = sys.argv[1:4]
extra = sys.argv[4:]

def order(c):
    if c == '~': return -1
    if c.isalpha(): return ord(c)
    return ord(c) + 256

def cmp_part(a, b):
    while a or b:
        i = 0
        while i < len(a) and not a[i].isdigit(): i += 1
        j = 0
        while j < len(b) and not b[j].isdigit(): j += 1
        pa, pb = a[:i], b[:j]
        a, b = a[i:], b[j:]
        for k in range(max(len(pa), len(pb))):
            ca = order(pa[k]) if k < len(pa) else 0
            cb = order(pb[k]) if k < len(pb) else 0
            if ca != cb: return -1 if ca < cb else 1
        i = 0
        while i < len(a) and a[i].isdigit(): i += 1
        j = 0
        while j < len(b) and b[j].isdigit(): j += 1
        na, nb = int(a[:i] or 0), int(b[:j] or 0)
        a, b = a[i:], b[j:]
        if na != nb: return -1 if na < nb else 1
    return 0

def split(v):
    epoch = 0
    if ':' in v:
        e, v = v.split(':', 1)
        epoch = int(e)
    rev = ''
    if '-' in v:
        v, rev = v.rsplit('-', 1)
    return epoch, v, rev

def vercmp(x, y):
    ex, ux, rx = split(x)
    ey, uy, ry = split(y)
    if ex != ey: return -1 if ex < ey else 1
    return cmp_part(ux, uy) or cmp_part(rx, ry)

debs = []
for root, dirs, files in os.walk(src):
    dirs.sort()
    for f in sorted(files):
        if f.endswith('.deb'):
            debs.append((os.path.join(root, f), root != src))
for e in extra:
    debs.append((os.path.abspath(e), False))

best = {}
allv = {}
identities = {}
for path, nested in debs:
    r = subprocess.run(['dpkg-deb', '-f', path, 'Package', 'Version', 'Architecture', 'Source'],
                       capture_output=True, text=True, check=True).stdout
    f = {}
    for line in r.splitlines():
        if ':' in line and not line.startswith(' '):
            k, v = line.split(':', 1)
            f[k] = v.strip()
    pkg, ver, arch = f['Package'], f['Version'], f['Architecture']
    if arch not in ('amd64', 'i386', 'arm64', 'all'):
        raise SystemExit('unsupported repository architecture: ' + arch)
    identity = (pkg, ver, arch)
    with open(path, 'rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    previous = identities.setdefault(identity, (digest, path))
    if previous[0] != digest:
        raise SystemExit('conflicting archives for %s %s %s: %s and %s' %
                         (*identity, previous[1], path))
    sf = f.get('Source', pkg)
    srcname = sf.split()[0]
    srcver = sf[sf.index('(') + 1:sf.index(')')] if '(' in sf else ver
    key = (pkg, arch)
    allv.setdefault(key, []).append((ver, os.path.basename(path)))
    cur = best.get(key)
    # newest wins; the same version in the top folder beats the same one in carried/
    if cur is None or vercmp(ver, cur[0]) > 0 or (vercmp(ver, cur[0]) == 0 and cur[3] and not nested):
        best[key] = (ver, path, srcname, nested, srcver)

def pooldir(name):
    return name[:4] if name.startswith('lib') and len(name) > 3 else name[0]

with open(out_sel, 'w') as o:
    for (pkg, arch), (ver, path, srcname, _, _sv) in sorted(best.items()):
        o.write('\t'.join([path, 'pool/main/%s/%s/%s' % (pooldir(srcname), srcname, os.path.basename(path)),
                           pkg, ver, arch]) + '\n')
# Source packages: a .dsc counts when its version is the one a selected binary was built from.
srcdir = os.environ.get('SOURCES_DIR', '')
need = {}
for (pkg, arch), (ver, path, srcname, _, sv) in best.items():
    need.setdefault((srcname, sv), []).append(pkg)
matched = set()
if srcdir and os.path.isdir(srcdir):
    for fn in sorted(os.listdir(srcdir)):
        if not fn.endswith('.dsc'):
            continue
        txt = open(os.path.join(srcdir, fn), errors='replace').read()
        name = version = None
        files = []
        infiles = False
        for line in txt.splitlines():
            if line.startswith('Source:'): name = line.split(':', 1)[1].strip()
            elif line.startswith('Version:'): version = line.split(':', 1)[1].strip()
            elif line.startswith('Files:'): infiles = True; continue
            elif infiles and line.startswith(' '):
                p = line.split()
                if len(p) == 3: files.append(p[2])
                continue
            else: infiles = False
        if (name, version) in need and (name, version) not in matched:
            names = [fn] + files
            if all(os.path.isfile(os.path.join(srcdir, x)) for x in names):
                matched.add((name, version))
                with open(out_sel, 'a') as o:
                    for x in names:
                        o.write('\t'.join([os.path.join(srcdir, x), 'pool/main/%s/%s/%s' % (pooldir(name), name, x), name, version, 'source']) + '\n')
with open(out_left + '.nosource', 'w') as o:
    for (name, sv), pk in sorted(need.items()):
        if (name, sv) not in matched:
            o.write('%s %s (binaries: %s)\n' % (name, sv, ' '.join(sorted(pk))))
with open(out_left, 'w') as o:
    for (pkg, arch), vs in sorted(allv.items()):
        keep = best[(pkg, arch)][0]
        for ver, fn in sorted(vs):
            if ver != keep:
                o.write('%s (%s) left out, newest is %s\n' % (pkg, ver, keep))
PY
[ -s "$W/selection.tsv" ] || { echo "no .deb files found in $SRC" >&2; exit 1; }

# Every binary we publish, including carried packages, must have an lc1 proof.
# This runs before copying or signing anything. Rebuild unmarked packages at a
# new version; never stamp or alter a previously published .deb in place.
PYTHONPATH="$HERE/..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.release check-selection "$W/selection.tsv"

# Link and start gate (ORDER 198): what check-selection proves is the archive bytes, not that
# the programs run. Every package that is new to DEST and runs on this machine must resolve like
# its predecessor and start (lean/smoke.tsv). SPARKY_LC_PREVIOUS_DIR holds the known-good
# earlier builds to compare with. SPARKY_LC_ARCHIVE_CONFIG names explicit signed public archive
# sources and SPARKY_LC_SCRATCH owns the isolated APT state, cache, roots and evidence (lean/archive.md).
HOST_ARCH=$(dpkg --print-architecture)
: >"$W/link-debs.txt"
: >"$W/link-siblings.txt"
while IFS=$'\t' read -r from to _ _ arch; do
	case "$arch" in
		"$HOST_ARCH"|all) ;;
		source) continue ;;
		*) echo "lc1 link: unsupported execution gate for $arch on $HOST_ARCH; foreign package not runtime-qualified: $from" >&2; continue ;;
	esac
	case $from in *-dbgsym_*|*-lc-hr_*) continue ;; esac
	echo "$from" >>"$W/link-siblings.txt"
	[ -f "$DEST/$to" ] || echo "$from" >>"$W/link-debs.txt"
done <"$W/selection.tsv"
# The destination is the previous edition universe. New siblings cannot qualify
# a predecessor that requires their old exact versions. The optional historical
# directory adds earlier builds; unchanged packages stay in both snapshots.
python3 - "$DEST" "$HOST_ARCH" "$W/link-previous.txt" <<'PYOLD'
from pathlib import Path
import subprocess
import sys
root, native, output = sys.argv[1:]
with open(output, 'w') as stream:
    for path in sorted(Path(root).glob('pool/**/*.deb')):
        if '-dbgsym_' in path.name or '-lc-hr_' in path.name:
            continue
        arch = subprocess.check_output(['dpkg-deb', '-f', str(path), 'Architecture'], text=True).strip()
        if arch in (native, 'all'):
            stream.write(str(path) + '\n')
PYOLD
if [ -s "$W/link-debs.txt" ]; then
	mapfile -t LINK_DEBS <"$W/link-debs.txt"
	PYTHONPATH="$HERE/..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.release check-link "${LINK_DEBS[@]}" --siblings-file "$W/link-siblings.txt" \
		--previous-siblings-file "$W/link-previous.txt" \
		${SPARKY_LC_PREVIOUS_DIR:+--previous-dir "$SPARKY_LC_PREVIOUS_DIR"}
fi

# Reject all conflicting destinations before changing any pool file. A package or
# retained source archive is immutable once published; changed bytes need a new
# version/name, even when both copies have valid Lean Code proofs.
python3 - "$W/selection.tsv" "$DEST" <<'PY'
import hashlib
from pathlib import Path
import sys

selection, destination = sys.argv[1:]
selected = {}
for line in Path(selection).read_text().splitlines():
    source, relative, *_ = line.split('\t')
    with open(source, 'rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    previous = selected.setdefault(relative, digest)
    if previous != digest:
        raise SystemExit('conflicting selected pool path: ' + relative)
    target = Path(destination) / relative
    if target.exists():
        with target.open('rb') as stream:
            existing = hashlib.file_digest(stream, 'sha256').hexdigest()
        if existing != digest:
            raise SystemExit('published archive is immutable: ' + relative)
PY

# 2. Pool: copy new archives, then drop what is no longer selected.
mkdir -p "$DEST/pool/$COMPONENT"
cut -f2 "$W/selection.tsv" | sort >"$W/wanted.txt"
added=0
while IFS=$'\t' read -r from to _; do
	if [ -f "$DEST/$to" ] && cmp -s "$from" "$DEST/$to"; then continue; fi
	mkdir -p "$(dirname "$DEST/$to")"
	cp "$from" "$DEST/$to.tmp" && chmod 644 "$DEST/$to.tmp" && mv -f "$DEST/$to.tmp" "$DEST/$to"
	added=$((added + 1))
done <"$W/selection.tsv"
(cd "$DEST" && find pool -type f | sort) >"$W/present.txt"
removed=0
while read -r f; do
	rm -f "${DEST:?}/${f:?}"
	removed=$((removed + 1))
done < <(comm -13 "$W/wanted.txt" "$W/present.txt")
find "$DEST/pool" -mindepth 1 -type d -empty -delete 2>/dev/null || true

# 3. Indexes, compressed, and the by-hash copies.
D=$DEST/dists/$CODENAME
sums=()
# index_done DIR REL NAME...: compress DIR/NAME (already written), copy all three by hash, list them
index_done() {
	local dir=$1 rel=$2 name f h live=
	shift 2
	mkdir -p "$dir/by-hash/SHA256"
	for name in "$@"; do
		gzip -9n -c "$dir/$name" >"$dir/$name.gz"
		xz -9e -T1 -c "$dir/$name" >"$dir/$name.xz"
		chmod 644 "$dir/$name"*
		for f in "$name" "$name.gz" "$name.xz"; do
			h=$(sha256sum "$dir/$f" | cut -d' ' -f1)
			cp -f "$dir/$f" "$dir/by-hash/SHA256/$h"
			chmod 644 "$dir/by-hash/SHA256/$h"
			sums+=("$h $(stat -c %s "$dir/$f") $rel/$f")
			live="$live $h"
		done
	done
	# by-hash files of older indexes stay a few days for clients mid-update, then go
	for f in "$dir"/by-hash/SHA256/*; do
		case " $live " in *" $(basename "$f") "*) continue ;; esac
		if [ -n "$(find "$f" -mtime +"$KEEP_BYHASH_DAYS" -print 2>/dev/null)" ]; then
			rm -f "${f:?}"
		fi
	done
}
# amd64 always; other supported architectures only when selected packages exist.
ARCHES=amd64
for a in i386 arm64 all; do
	if grep -q $'\t'"$a"$'$' "$W/selection.tsv"; then ARCHES="$ARCHES $a"; else rm -rf "${D:?}/$COMPONENT/binary-$a"; fi
done
for arch in $ARCHES; do
	dir=$D/$COMPONENT/binary-$arch
	mkdir -p "$dir"
	# dpkg-scanpackages --arch amd64 also lists Architecture: all; keep each index to its own
	# Selection already chose one version per architecture. Keep architecture
	# siblings until the filter; scanpackages otherwise collapses by name alone.
	(cd "$DEST" && dpkg-scanpackages --multiversion --arch "$arch" pool /dev/null 2>"$W/scan-$arch.log") |
		awk -v RS= -v ORS='\n\n' -v a="Architecture: $arch" 'index($0, "\n" a "\n") || $0 ~ ("\n" a "$")' |
		sed '$d' >"$dir/Packages.new"
	grep -v -e '^dpkg-scanpackages: info:' -e '^dpkg-scanpackages: warning:' "$W/scan-$arch.log" >&2 || true
	mv -f "$dir/Packages.new" "$dir/Packages"
	index_done "$dir" "$COMPONENT/binary-$arch" Packages
done
dir=$D/$COMPONENT/source
if grep -q $'\tsource$' "$W/selection.tsv"; then
	mkdir -p "$dir"
	(cd "$DEST" && dpkg-scansources pool /dev/null 2>"$W/scan-src.log") >"$dir/Sources.new"
	grep -v -e '^dpkg-scansources: info:' -e '^dpkg-scansources: warning:' "$W/scan-src.log" >&2 || true
	mv -f "$dir/Sources.new" "$dir/Sources"
	index_done "$dir" "$COMPONENT/source" Sources
else
	rm -rf "${dir:?}"
fi

# 3b. Contents files (apt-file and command-not-found read them): which package ships which path. Debian's
# format: "path<tab>section/package[,section/package]", sorted by path; Architecture: all packages are listed in
# every architecture's file and in Contents-all, as the archive does. Deterministic, so a run that changes
# nothing leaves the signed Release as it was.
mapfile -t CONTENTS_DEBS < <(awk -F'\t' '$5 != "source" {print $1}' "$W/selection.tsv")
python3 "$HERE/make-contents.py" "$W" "$ARCHES" "${CONTENTS_DEBS[@]}"
for arch in $ARCHES; do
	cp -f "$W/Contents-$arch" "$D/$COMPONENT/Contents-$arch"
done
index_done "$D/$COMPONENT" "$COMPONENT" $(for arch in $ARCHES; do echo "Contents-$arch"; done)

# 4. Release, signed. When nothing but the date would change, the signed files stay.
{
	echo "Origin: $ORIGIN"
	echo "Label: $ORIGIN"
	echo "Suite: $SUITE"
	echo "Codename: $CODENAME"
	echo "Version: $EDITION_VERSION"
	echo "Date: @DATE@"
	echo "Architectures: $ARCHES"
	echo "Components: $COMPONENT"
	echo "Description: $DESCRIPTION"
	echo "Acquire-By-Hash: yes"
	echo "SHA256:"
	printf '%s\n' "${sums[@]}" | sort -k3 | while read -r h s p; do printf ' %s %16s %s\n' "$h" "$s" "$p"; done
} >"$W/Release.tpl"
if [ -f "$D/Release" ] && [ -f "$D/InRelease" ] && [ -f "$D/Release.gpg" ] &&
	[ "$(grep -v '^Date: ' "$D/Release")" = "$(grep -v '^Date: ' "$W/Release.tpl")" ]; then
	signed=kept
else
	sed "s|@DATE@|$(date -u '+%a, %d %b %Y %H:%M:%S UTC')|" "$W/Release.tpl" >"$D/Release.new"
	"${GPG[@]}" -u "$SPARKY_REPO_KEY" --digest-algo SHA512 --detach-sign --armor -o "$D/Release.gpg.new" "$D/Release.new"
	"${GPG[@]}" -u "$SPARKY_REPO_KEY" --digest-algo SHA512 --clearsign -o "$D/InRelease.new" "$D/Release.new"
	chmod 644 "$D"/*.new
	mv -f "$D/Release.new" "$D/Release"
	mv -f "$D/Release.gpg.new" "$D/Release.gpg"
	mv -f "$D/InRelease.new" "$D/InRelease"
	signed=signed
fi

# 5. The public key (armoured, as SparkyLinux serves theirs) and the page.
rm -f "$DEST/sparky-stereo-archive-keyring.gpg" "$DEST/sparky-stereo-archive-keyring.asc"
"${GPG[@]}" --armor --export "$FPR" >"$DEST/sparky-stereo-repo.asc"
FPR_SPACED=$(echo "$FPR" | sed 's/.\{4\}/& /g; s/ $//')
sed "s/@FINGERPRINT@/$FPR_SPACED/" "$HERE/index.html" >"$DEST/index.html"
chmod 644 "$DEST/sparky-stereo-repo.asc" "$DEST/index.html"

echo "tree $DEST: $(grep -vc $'\tsource$' "$W/selection.tsv") packages, $(grep -c $'\tsource$' "$W/selection.tsv") source files, $added copied, $removed removed from the pool, Release $signed"
echo "key fingerprint: $FPR_SPACED"
if [ -s "$W/leftout.txt.nosource" ]; then
	echo "source packages missing ($(wc -l <"$W/leftout.txt.nosource")): $(grep -q $'\tsource$' "$W/selection.tsv" && echo "partial sources index" || echo "no sources index, use Types: deb")"
	sed 's/^/  /' "$W/leftout.txt.nosource"
fi
if [ -s "$W/leftout.txt" ]; then
	echo "older versions left out ($(wc -l <"$W/leftout.txt")):"
	sed 's/^/  /' "$W/leftout.txt"
fi
