#!/bin/bash
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/05
# Copyright 2026 under the GNU GPL3 License
# Turns the flat development repository (make-repo.sh) into the public, signed apt tree of
# Sparky Stereo OS 9 "Mashtabba" (Debian 14 "Forky"), in the standard Debian layout:
#   pool/main/<first letter or libX>/<source name>/*.deb
#   dists/mashtabba/Release, InRelease, Release.gpg
#   dists/mashtabba/main/binary-amd64/Packages{,.gz,.xz}   (Architecture: amd64)
#   dists/mashtabba/main/binary-all/Packages{,.gz,.xz}     (Architecture: all, as apt asks for them)
#   .../by-hash/SHA256/<hash>   (Acquire-By-Hash: yes; the last days' files are kept for
#                                clients that are in the middle of an update)
#   index.html, sparky-stereo-archive-keyring.gpg and .asc (the public key, exported here)
# Only the newest version of each package (per architecture) goes into the tree; the older
# ones left out are listed. SRC (also its carried/ folder) is only read, never written.
# Safe to run again: unchanged pool files are kept, files of versions that are no longer the
# newest are removed from the pool, and when nothing changed the signed Release stays as it was.
#
# Usage: SPARKY_REPO_KEY=<fingerprint> SPARKY_REPO_GNUPGHOME=<gnupg home> \
#        publish-tree.sh SRC DEST [extra.deb ...]
#   extra.deb: more packages to include (for example the sparky-stereo-keyring package).
# With a key that has a passphrase, gpg-agent asks for it once (run from a terminal); it
# stays cached for the run. A key without a passphrase signs without asking.
# Last update 2026/10/05
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SUITE=mashtabba
COMPONENT=main
EDITION_VERSION=9
DESCRIPTION="Sparky Stereo OS 9 Mashtabba: the stereo stack and the edition's own packages"
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

W=$(mktemp -d "${TMPDIR:-/K3D/temp}/publish-tree.XXXXXX")
trap 'rm -rf "${W:?}"' EXIT

# 1. Choose the newest version of each package and where it goes in the pool.
python3 - "$SRC" "$W/selection.tsv" "$W/leftout.txt" "${EXTRA[@]}" <<'PY'
import os, sys, subprocess

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
for path, nested in debs:
    r = subprocess.run(['dpkg-deb', '-f', path, 'Package', 'Version', 'Architecture', 'Source'],
                       capture_output=True, text=True, check=True).stdout
    f = {}
    for line in r.splitlines():
        if ':' in line and not line.startswith(' '):
            k, v = line.split(':', 1)
            f[k] = v.strip()
    pkg, ver, arch = f['Package'], f['Version'], f['Architecture']
    srcname = f.get('Source', pkg).split()[0]
    key = (pkg, arch)
    allv.setdefault(key, []).append((ver, os.path.basename(path)))
    cur = best.get(key)
    # newest wins; the same version in the top folder beats the same one in carried/
    if cur is None or vercmp(ver, cur[0]) > 0 or (vercmp(ver, cur[0]) == 0 and cur[3] and not nested):
        best[key] = (ver, path, srcname, nested)

def pooldir(name):
    return name[:4] if name.startswith('lib') and len(name) > 3 else name[0]

with open(out_sel, 'w') as o:
    for (pkg, arch), (ver, path, srcname, _) in sorted(best.items()):
        o.write('\t'.join([path, 'pool/main/%s/%s/%s' % (pooldir(srcname), srcname, os.path.basename(path)),
                           pkg, ver, arch]) + '\n')
with open(out_left, 'w') as o:
    for (pkg, arch), vs in sorted(allv.items()):
        keep = best[(pkg, arch)][0]
        for ver, fn in sorted(vs):
            if ver != keep:
                o.write('%s (%s) left out, newest is %s\n' % (pkg, ver, keep))
PY
[ -s "$W/selection.tsv" ] || { echo "no .deb files found in $SRC" >&2; exit 1; }

# 2. Pool: copy what is new or changed, then drop what is no longer selected.
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
D=$DEST/dists/$SUITE
sums=()
for arch in amd64 all; do
	dir=$D/$COMPONENT/binary-$arch
	if [ "$arch" != amd64 ] && ! grep -q $'\tall$' "$W/selection.tsv"; then
		rm -rf "${dir:?}"
		continue
	fi
	mkdir -p "$dir"
	# dpkg-scanpackages --arch amd64 also lists Architecture: all; keep each index to its own
	(cd "$DEST" && dpkg-scanpackages --arch "$arch" pool /dev/null 2>"$W/scan-$arch.log") |
		awk -v RS= -v ORS='\n\n' -v a="Architecture: $arch" 'index($0, "\n" a "\n") || $0 ~ ("\n" a "$")' |
		sed '$d' >"$dir/Packages.new"
	grep -v -e '^dpkg-scanpackages: info:' -e '^dpkg-scanpackages: warning:' "$W/scan-$arch.log" >&2 || true
	mv -f "$dir/Packages.new" "$dir/Packages"
	gzip -9n -c "$dir/Packages" >"$dir/Packages.gz"
	xz -9e -T1 -c "$dir/Packages" >"$dir/Packages.xz"
	chmod 644 "$dir"/Packages*
	mkdir -p "$dir/by-hash/SHA256"
	live=
	for f in Packages Packages.gz Packages.xz; do
		h=$(sha256sum "$dir/$f" | cut -d' ' -f1)
		cp -f "$dir/$f" "$dir/by-hash/SHA256/$h"
		chmod 644 "$dir/by-hash/SHA256/$h"
		sums+=("$h $(stat -c %s "$dir/$f") $COMPONENT/binary-$arch/$f")
		live="$live $h"
	done
	# by-hash files of older indexes stay a few days for clients mid-update, then go
	for old in "$dir"/by-hash/SHA256/*; do
		case " $live " in *" $(basename "$old") "*) continue ;; esac
		if [ -n "$(find "$old" -mtime +"$KEEP_BYHASH_DAYS" -print 2>/dev/null)" ]; then
			rm -f "${old:?}"
		fi
	done
done

# 4. Release, signed. When nothing but the date would change, the signed files stay.
{
	echo "Origin: Sparky Stereo"
	echo "Label: Sparky Stereo"
	echo "Suite: $SUITE"
	echo "Codename: $SUITE"
	echo "Version: $EDITION_VERSION"
	echo "Date: @DATE@"
	echo "Architectures: amd64 all"
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

# 5. The public key and the page.
"${GPG[@]}" --export "$FPR" >"$DEST/sparky-stereo-archive-keyring.gpg"
"${GPG[@]}" --armor --export "$FPR" >"$DEST/sparky-stereo-archive-keyring.asc"
FPR_SPACED=$(echo "$FPR" | sed 's/.\{4\}/& /g; s/ $//')
sed "s/@FINGERPRINT@/$FPR_SPACED/" "$HERE/index.html" >"$DEST/index.html"
chmod 644 "$DEST"/sparky-stereo-archive-keyring.* "$DEST/index.html"

echo "tree $DEST: $(wc -l <"$W/selection.tsv") packages, $added copied, $removed removed from the pool, Release $signed"
echo "key fingerprint: $FPR_SPACED"
if [ -s "$W/leftout.txt" ]; then
	echo "older versions left out ($(wc -l <"$W/leftout.txt")):"
	sed 's/^/  /' "$W/leftout.txt"
fi
