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
#   dists/mashtabba/main/dep11/Components-<arch>.yml{,.gz}  (optional, with SPARKY_APPSTREAM=1; AppStream, with icons)
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
#        [SPARKY_APPSTREAM=1 SPARKY_APPSTREAM_IMAGE=<Debian testing image with appstream-generator> \
#         SPARKY_APPSTREAM_USER=1000:1000] \
#        publish-tree.sh SRC DEST [extra.deb ...]
#   extra.deb: more packages to include (for example the sparky-stereo-keyring package).
# With a key that has a passphrase, gpg-agent asks for it once (run from a terminal); it
# stays cached for the run. A key without a passphrase signs without asking.
<<<<<<< HEAD
# Last update 2026/10/30 (DEP-11 catalogues, ORDER 252b)
=======
# Installability (ORDER 317): before Release is signed, check-installable.py asks whether every package of the new tree
# installs on a fresh edition from the archives it uses (SPARKY_LC_ARCHIVE_CONFIG; the CUDA repository too). Its report
# goes to SPARKY_INSTALLABLE_REPORT (default SPARKY_LC_SCRATCH/installable/report-<time>). SPARKY_INSTALLABLE=report (the
# default) prints it and goes on; refuse stops before signing when a package fails that SPARKY_INSTALLABLE_KNOWN
# (package<TAB>version or *<TAB>reason) does not list; off skips the check.
# Last update 2026/10/31 (installability report, ORDER 317)
>>>>>>> bd46151204159e4298126d7dddf39fde66ac75af
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
SPARKY_APPSTREAM=${SPARKY_APPSTREAM-}
case "$SPARKY_APPSTREAM" in
    1|'') ;;
    *) echo "SPARKY_APPSTREAM must be 1 when set" >&2; exit 2 ;;
esac
if [ "$SPARKY_APPSTREAM" = 1 ]; then
    : "${SPARKY_APPSTREAM_IMAGE:?set SPARKY_APPSTREAM_IMAGE to a Debian testing image with appstream-generator}"
    : "${SPARKY_APPSTREAM_USER:?set SPARKY_APPSTREAM_USER to 1000:1000}"
    [ "$SPARKY_APPSTREAM_USER" = 1000:1000 ] || { echo "the AppStream generator must run as user 1000:1000" >&2; exit 2; }
fi
SCRATCH=${TMPDIR:-${SPARKY_SCRATCH:?}}
[ -d "$SCRATCH" ] || { echo "scratch directory is missing: $SCRATCH" >&2; exit 2; }
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

W=$(mktemp -d "$SCRATCH/publish-tree.XXXXXX")
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
PYTHONPATH="$HERE/..${PYTHONPATH:+:$PYTHONPATH}" python3 - "$DEST" "$HOST_ARCH" "$W/link-previous.txt" "$CODENAME" <<'PYOLD'
from pathlib import Path, PurePosixPath
import sys
from lean import archive
root, native, output, codename = sys.argv[1:]
root = Path(root)
metadata = root / 'dists' / codename
previous = {}
release = metadata / 'Release'
if not release.is_file() and any((metadata / name).exists() for name in ('InRelease', 'Release.gpg')):
    raise SystemExit('previous edition Release missing: ' + str(release))
if release.is_file():
    # Missing known previous archives must block, rather than making an existing
    # package appear to have no predecessor. Bind each old input to its index.
    release_fields = archive.fields(release.read_text())
    arches = release_fields.get('Architectures', '').split()
    hashes = {parts[2]: (parts[0], parts[1]) for line in release_fields.get('SHA256', '').splitlines()
              if len(parts := line.split()) == 3}
    if not arches:
        raise SystemExit('previous edition Release has no architectures')
    for arch in dict.fromkeys((native, 'all')):
        if arch not in arches:
            continue
        index = metadata / 'main' / ('binary-' + arch) / 'Packages'
        if not index.is_file():
            raise SystemExit('previous edition index missing: ' + str(index))
        expected = hashes.get(str(index.relative_to(metadata)))
        if expected != (archive.digest(index), str(index.stat().st_size)):
            raise SystemExit('previous edition index differs from its Release: ' + str(index))
        for stanza in index.read_text().split('\n\n'):
            obj = archive.fields(stanza)
            name = obj.get('Package', '')
            if not name or name.endswith(('-lc-hr', '-dbgsym')):
                continue
            if obj.get('Architecture') not in (native, 'all'):
                raise SystemExit('wrong architecture in previous edition index: ' + name)
            relative = PurePosixPath(obj.get('Filename', ''))
            if relative.is_absolute() or '..' in relative.parts or not relative.parts or relative.parts[0] != 'pool':
                raise SystemExit('unsafe previous edition archive path: ' + str(relative))
            path = root / relative
            if not path.is_file():
                raise SystemExit('previous edition archive missing: ' + str(path))
            if str(path.stat().st_size) != obj.get('Size') or archive.digest(path) != obj.get('SHA256'):
                raise SystemExit('previous edition archive differs from its index: ' + str(path))
            if archive.identity(archive.control(path)) != archive.identity(obj):
                raise SystemExit('previous edition archive identity differs from its index: ' + str(path))
            key = (name, obj['Architecture'])
            if key in previous and previous[key] != path:
                raise SystemExit('conflicting previous edition index identity: ' + name)
            previous[key] = path
else:
    # A first publication can have an unindexed retained cohort supplied in its
    # destination. There is no signed publication history to infer missing files.
    for path in sorted(root.glob('pool/**/*.deb')):
        obj = archive.control(path)
        if obj['Package'].endswith(('-lc-hr', '-dbgsym')):
            continue
        if obj['Architecture'] in (native, 'all'):
            previous[(obj['Package'], obj['Architecture'])] = path
with open(output, 'w') as stream:
    for path in sorted(previous.values()):
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

# 2. DEP-11, generated before any destination file changes. The temporary archive
# links only the selected inputs, so a generator failure leaves DEST untouched and
# does not duplicate the repository in scratch.
# amd64 always; other supported architectures only when selected packages exist.
ARCHES=amd64
for architecture in i386 arm64 all; do
	if grep -q $'\t'"$architecture"$'$' "$W/selection.tsv"; then ARCHES="$ARCHES $architecture"; fi
done
if [ "$SPARKY_APPSTREAM" = 1 ]; then
DEP11=$W/dep11
DEP11_ARCHIVE=$DEP11/archive
rm -rf -- "$DEP11"
mkdir -p "$DEP11_ARCHIVE"
python3 - "$W/selection.tsv" "$DEP11_ARCHIVE" "$DEP11/mounts.txt" <<'PY'
import os, sys

selection, archive, mounts = sys.argv[1:]
roots = set()
selected = {}
with open(selection) as stream:
    for line in stream:
        path, relative, *_ = line.rstrip('\n').split('\t')
        real = os.path.realpath(path)
        if relative in selected:
            if selected[relative] != real:
                raise SystemExit('conflicting selected archive path: ' + relative)
            continue
        selected[relative] = real
        target = os.path.join(archive, relative)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        os.symlink(real, target)
        if real.endswith('/' + relative):
            roots.add(real[:-len(relative) - 1])
        else:
            roots.add(os.path.dirname(real))
with open(mounts, 'w') as stream:
    for root in sorted(roots):
        stream.write(root + '\n')
PY
APPSTREAM_ARCHES=$(printf '%s\n' $ARCHES | grep -vx all | paste -sd, - |
	sed 's/[^,]*/"&"/g')
for architecture in $ARCHES; do
	dir=$DEP11_ARCHIVE/dists/$CODENAME/$COMPONENT/binary-$architecture
	mkdir -p "$dir"
	(cd "$DEP11_ARCHIVE" && dpkg-scanpackages --multiversion --arch "$architecture" pool /dev/null 2>"$W/dep11-scan-$architecture.log") |
		awk -v RS= -v ORS='\n\n' -v architecture="$architecture" '
			index($0, "\nArchitecture: all\n") || $0 ~ ("\nArchitecture: all$") ||
			index($0, "\nArchitecture: " architecture "\n") || $0 ~ ("\nArchitecture: " architecture "$")' |
		sed '$d' >"$dir/Packages"
	gzip -9n -c "$dir/Packages" >"$dir/Packages.gz"
	xz -9e -T1 -c "$dir/Packages" >"$dir/Packages.xz"
	grep -v -e '^dpkg-scanpackages: info:' -e '^dpkg-scanpackages: warning:' "$W/dep11-scan-$architecture.log" >&2 || true
done
mkdir -p "$DEP11/config" "$DEP11/workspace"
cat >"$DEP11/config/config.json" <<EOF
{
  "ArchiveRoot": "/dep11/archive",
  "ProjectName": "$ORIGIN",
  "Backend": "debian",
  "MetadataType": "YAML",
  "Suites": {
    "$CODENAME": {
      "sections": ["$COMPONENT"],
      "architectures": [$APPSTREAM_ARCHES]
    }
  },
  "Features": {
    "processDesktop": true,
    "createScreenshotsStore": false,
    "noDownloads": true,
    "metadataTimestamps": false
  }
}
EOF
# The image runs as 1000:1000, with four CPUs, no network, and only the roots
# needed by the selected inputs mounted read-only.
APPSTREAM_DOCKER=(docker run --rm --cpus 4 --user "$SPARKY_APPSTREAM_USER" --network none -v "$DEP11:/dep11")
while IFS= read -r root; do
	APPSTREAM_DOCKER+=(-v "$root:$root:ro")
done <"$DEP11/mounts.txt"
APPSTREAM_DOCKER+=("$SPARKY_APPSTREAM_IMAGE")
"${APPSTREAM_DOCKER[@]}" \
	appstream-generator -c /dep11/config/config.json -w /dep11/workspace run "$CODENAME" "$COMPONENT"
if [ -n "${SPARKY_APPSTREAM_MAX_BYTES:-}" ]; then
	case "$SPARKY_APPSTREAM_MAX_BYTES" in
		''|*[!0-9]*) echo "SPARKY_APPSTREAM_MAX_BYTES must be a byte count" >&2; exit 2 ;;
	esac
	appstream_workspace_bytes=$(du -sb "$DEP11" | cut -f1)
	[ "$appstream_workspace_bytes" -le "$SPARKY_APPSTREAM_MAX_BYTES" ] || {
		echo "AppStream workspace exceeds ${SPARKY_APPSTREAM_MAX_BYTES} bytes: $DEP11 ($appstream_workspace_bytes bytes)" >&2
		exit 2
	}
fi
DEP11_DATA=$DEP11/workspace/export/data/$CODENAME/$COMPONENT
DEP11_STAGED=$DEP11/publish
mkdir -p "$DEP11_STAGED"
python3 - "$DEP11_DATA" "$DEP11_STAGED" <<'PY'
import gzip
import io
import os
import sys
import tarfile
from pathlib import Path

source_dir, target_dir = (Path(argument) for argument in sys.argv[1:])
for source in sorted(source_dir.glob("icons-*.tar.gz")):
    target = target_dir / source.name
    temporary = target.with_suffix(target.suffix + ".tmp")
    with source.open("rb") as raw:
        with gzip.GzipFile(fileobj=raw, mode="rb") as compressed:
            with tarfile.open(fileobj=compressed, mode="r:") as archive:
                members = sorted(archive.getmembers(), key=lambda member: member.name)
                if any(not member.isfile() for member in members):
                    raise SystemExit("the AppStream generator made a non-file icon entry: " + source.name)
                with temporary.open("wb") as output:
                    with gzip.GzipFile(filename="", mode="wb", compresslevel=9, fileobj=output, mtime=0) as normalized:
                        with tarfile.open(fileobj=normalized, mode="w", format=tarfile.PAX_FORMAT) as tar:
                            for member in members:
                                info = tarfile.TarInfo(member.name)
                                info.size = member.size
                                info.mtime = 0
                                info.mode = 0o644
                                info.type = tarfile.REGTYPE
                                info.uid = 0
                                info.gid = 0
                                info.uname = ""
                                info.gname = ""
                                data = archive.extractfile(member).read()
                                tar.addfile(info, io.BytesIO(data))
    os.replace(temporary, target)
PY
DEP11_FILES=()
for architecture in $ARCHES; do
	[ "$architecture" = all ] && continue
	name=Components-$architecture.yml.gz
	[ -f "$DEP11_DATA/$name" ] || { echo "the AppStream generator made no $name" >&2; exit 1; }
	cp "$DEP11_DATA/$name" "$DEP11_STAGED/$name"
	gzip -dc "$DEP11_DATA/$name" >"$DEP11_STAGED/Components-$architecture.yml"
	DEP11_FILES+=(Components-$architecture.yml)
	DEP11_FILES+=("$name")
done
for name in icons-48x48 icons-64x64 icons-128x128; do
	[ -f "$DEP11_STAGED/$name.tar.gz" ] || { echo "the AppStream generator made no $name.tar.gz" >&2; exit 1; }
	DEP11_FILES+=("$name.tar.gz")
	if [ -f "$DEP11_STAGED/$name@2.tar.gz" ]; then
		DEP11_FILES+=("$name@2.tar.gz")
	fi
done
printf '%s\n' "${DEP11_FILES[@]}" | sort >"$DEP11/expected.txt"
if [ -d "$DEST/dists/$CODENAME/$COMPONENT/dep11" ]; then
	find "$DEST/dists/$CODENAME/$COMPONENT/dep11" -maxdepth 1 -type f -printf '%f\n' | sort >"$DEP11/present.txt"
else
	: >"$DEP11/present.txt"
fi
DEP11_CHANGED=0
cmp -s "$DEP11/expected.txt" "$DEP11/present.txt" || DEP11_CHANGED=1
for name in "${DEP11_FILES[@]}"; do
	cmp -s "$DEP11_STAGED/$name" "$DEST/dists/$CODENAME/$COMPONENT/dep11/$name" || DEP11_CHANGED=1
done
fi

# 3. Pool: copy new archives, then drop what is no longer selected.
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

# 4. Indexes, compressed, and the by-hash copies.
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
for arch in $ARCHES; do
	dir=$D/$COMPONENT/binary-$arch
	if [ "$arch" != amd64 ] && ! grep -q $'\t'"$arch"$'$' "$W/selection.tsv"; then
		rm -rf "${dir:?}"
		continue
	fi
	stage=$W/index-binary-$arch
	mkdir -p "$stage"

	# dpkg-scanpackages --arch amd64 also lists Architecture: all; keep each index to its own
	# Selection already chose one version per architecture. Keep architecture
	# siblings until the filter; scanpackages otherwise collapses by name alone.
	(cd "$DEST" && dpkg-scanpackages --multiversion --arch "$arch" pool /dev/null 2>"$W/scan-$arch.log") |
		awk -v RS= -v ORS='\n\n' -v a="Architecture: $arch" 'index($0, "\n" a "\n") || $0 ~ ("\n" a "$")' |
		sed '$d' >"$stage/Packages"

	grep -v -e '^dpkg-scanpackages: info:' -e '^dpkg-scanpackages: warning:' "$W/scan-$arch.log" >&2 || true
	index_done "$stage" "$COMPONENT/binary-$arch" Packages
	mkdir -p "$dir"
	for name in Packages Packages.gz Packages.xz; do
		cp "$stage/$name" "$dir/$name.tmp"
		chmod 644 "$dir/$name.tmp"
		mv -f "$dir/$name.tmp" "$dir/$name"
	done
	cp -a "$stage/by-hash" "$dir/"

done
dir=$D/$COMPONENT/source
if grep -q $'\tsource$' "$W/selection.tsv"; then
	mkdir -p "$dir"
	stage=$W/index-source
	mkdir -p "$stage"
	(cd "$DEST" && dpkg-scansources pool /dev/null 2>"$W/scan-src.log") >"$stage/Sources"

	grep -v -e '^dpkg-scansources: info:' -e '^dpkg-scansources: warning:' "$W/scan-src.log" >&2 || true
	index_done "$stage" "$COMPONENT/source" Sources
	mkdir -p "$dir"
	for name in Sources Sources.gz Sources.xz; do
		cp "$stage/$name" "$dir/$name.tmp"
		chmod 644 "$dir/$name.tmp"
		mv -f "$dir/$name.tmp" "$dir/$name"
	done
	cp -a "$stage/by-hash" "$dir/"

else
	source_existing=true
	for name in Sources Sources.gz Sources.xz; do
		[ -f "$dir/$name" ] || source_existing=false
	done
	if [ "$source_existing" = true ]; then
		for name in Sources Sources.gz Sources.xz; do
			source_hash=$(sha256sum "$dir/$name" | cut -d' ' -f1)
			sums+=("$source_hash $(stat -c %s "$dir/$name") $COMPONENT/source/$name")
		done
	else
		rm -rf "${dir:?}"
	fi
fi

# 4b. Contents files (apt-file and command-not-found read them): which package ships which path. Debian's
# format: "path<tab>section/package[,section/package]", sorted by path; Architecture: all packages are listed in
# every architecture's file and in Contents-all, as the archive does. Deterministic, so a run that changes
# nothing leaves the signed Release as it was.
mapfile -t CONTENTS_DEBS < <(awk -F'\t' '$5 != "source" {print $1}' "$W/selection.tsv")
python3 "$HERE/make-contents.py" "$W" "$ARCHES" "${CONTENTS_DEBS[@]}"
for arch in $ARCHES; do
	cp -f "$W/Contents-$arch" "$D/$COMPONENT/Contents-$arch"
done
index_done "$D/$COMPONENT" "$COMPONENT" $(for arch in $ARCHES; do echo "Contents-$arch"; done)

<<<<<<< HEAD
# 4c. Publish only the generated DEP-11 catalogues and icon tarballs; the generator's
# cache, hints, CID index, HTML, statistics and compressed xz catalogues stay outside.
if [ "$SPARKY_APPSTREAM" = 1 ]; then
DEP11_DIR=$D/$COMPONENT/dep11
if [ "$DEP11_CHANGED" = 1 ]; then
	mkdir -p "$DEP11_DIR"
	while IFS= read -r name; do
		rm -f "${DEP11_DIR:?}/${name:?}"
	done < <(comm -23 "$DEP11/present.txt" "$DEP11/expected.txt")
	for name in "${DEP11_FILES[@]}"; do
		cp "$DEP11_STAGED/$name" "$DEP11_DIR/$name.tmp"
		chmod 644 "$DEP11_DIR/$name.tmp"
		mv -f "$DEP11_DIR/$name.tmp" "$DEP11_DIR/$name"
	done
fi
dep11_done() {
	local dir=$1 rel=$2 name f h live=
	shift 2
	mkdir -p "$dir/by-hash/SHA256"
	for name in "$@"; do
		h=$(sha256sum "$dir/$name" | cut -d' ' -f1)
		cp -f "$dir/$name" "$dir/by-hash/SHA256/$h"
		chmod 644 "$dir/by-hash/SHA256/$h"
		sums+=("$h $(stat -c %s "$dir/$name") $rel/$name")
		live="$live $h"
	done
	for f in "$dir"/by-hash/SHA256/*; do
		case " $live " in *" $(basename "$f") "*) continue ;; esac
		if [ -n "$(find "$f" -mtime +"$KEEP_BYHASH_DAYS" -print 2>/dev/null)" ]; then
			rm -f "${f:?}"
		fi
	done
}
dep11_done "$DEP11_DIR" "$COMPONENT/dep11" "${DEP11_FILES[@]}"
fi

# 5. Release, signed. When nothing but the date would change, the signed files stay.
=======
# 3c. Installability (ORDER 317). A package can stop installing after we published it, with no change on our side:
# Debian testing moves a library to a new soname and our build still depends on the old one (kdenlive 26.08.1-1+stereo3d5
# and libkddockwidgets-qt6-3, 31 October 2026). The indexes above are this run's own, so they are read unsigned.
case ${SPARKY_INSTALLABLE:-report} in
	off) echo "installability: not checked (SPARKY_INSTALLABLE=off)" ;;
	report | refuse)
		INSTALLABLE_REPORT=${SPARKY_INSTALLABLE_REPORT:-${SPARKY_LC_SCRATCH:?set SPARKY_LC_SCRATCH or SPARKY_INSTALLABLE_REPORT}/installable/report-$(date -u +%Y%m%dT%H%M%SZ)}
		installable=0
		python3 "$HERE/check-installable.py" "$DEST" --codename "$CODENAME" --unsigned --mode "${SPARKY_INSTALLABLE:-report}" \
			--report "$INSTALLABLE_REPORT" ${SPARKY_INSTALLABLE_KNOWN:+--known "$SPARKY_INSTALLABLE_KNOWN"} || installable=$?
		if [ "$installable" -ne 0 ]; then
			if [ "${SPARKY_INSTALLABLE:-report}" = refuse ]; then
				echo "installability: refused before signing (exit $installable); see $INSTALLABLE_REPORT/summary.txt" >&2
				exit 1
			fi
			echo "installability: the check did not finish (exit $installable); the publication goes on without it (SPARKY_INSTALLABLE=report)" >&2
		fi ;;
	*) echo "SPARKY_INSTALLABLE must be report, refuse or off" >&2; exit 2 ;;
esac

# 4. Release, signed. When nothing but the date would change, the signed files stay.
>>>>>>> bd46151204159e4298126d7dddf39fde66ac75af
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

# 6. The public key (armoured, as SparkyLinux serves theirs) and the page.
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
