#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/15
# Copyright 2026 under the GNU GPL3 License
# Build the merged layer once, followed by Dolphin from its accepted source.
# Usage: merged-round.sh WORK FORK REV PUBLISHED ARCHIVE STAGE_551 STAGE_551B DOLPHIN_SOURCE
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
DEPTH=$HERE/../depth-source
W=$(mkdir -p "$1" && cd "$1" && pwd)
FORK=$(cd "$2" && pwd) REV=$3 TREE=$(cd "$4" && pwd) ARCHIVE=$(cd "$5" && pwd)
STAGE_551=$(cd "$6" && pwd) STAGE_551B=$(cd "$7" && pwd) DOLPHIN=$(cd "$8" && pwd)
export BUILD_NAME_PREFIX=${BUILD_NAME_PREFIX:-rp-580-build} THREADS=${THREADS:-4}
export SPARKY_BUILD_IMAGE=${SPARKY_BUILD_IMAGE:-sparky-lc-migration:20261020}
ROUND='stereo-layer dolphin kf6-kimageformats kio-extras ffmpegthumbs gwenview koko kphotoalbum digikam'
mkdir -p "$W/new"
disk() {
    df -BG / /mnt/build
    [ "$(df -B1 --output=avail / | tail -1)" -ge 25000000000 ] &&
        [ "$(df -B1 --output=avail /mnt/build | tail -1)" -ge 8000000000 ] || {
        echo 'Disk floor reached; stopping the round.' >&2; exit 1;
    }
}
index() {
    python3 - "$W/new" <<'PY'
import hashlib, pathlib, subprocess, sys
root = pathlib.Path(sys.argv[1])
rows = []
for path in sorted(root.glob('*.deb')):
    control = subprocess.check_output(['dpkg-deb', '-f', str(path)], text=True).rstrip()
    data = path.read_bytes()
    rows.append(f'{control}\nFilename: ./{path.name}\nSize: {len(data)}\nSHA256: {hashlib.sha256(data).hexdigest()}\n')
packages = '\n'.join(rows).encode()
(root / 'Packages').write_bytes(packages)
(root / 'Release').write_text('Origin: Sparky Stereo OS\nLabel: merged stereo round\nArchitectures: amd64 all\nSHA256:\n'
    f' {hashlib.sha256(packages).hexdigest()} {len(packages)} Packages\n')
PY
}
if [ ! -f "$W/seed.done" ]; then
    for src in kf6-kimageformats kio-extras ffmpegthumbs gwenview; do
        cp --no-preserve=links "$STAGE_551/$src"/*.deb "$W/new/"
    done
    for src in koko kphotoalbum digikam; do
        cp --no-preserve=links "$STAGE_551B/$src"/*.deb "$W/new/"
    done
    touch "$W/seed.done"
fi
(cd "$TREE" && find pool -name '*.deb' ! -name '*-lc-hr_*' ! -name '*-dbgsym_*' | LC_ALL=C sort | sed 's|^|/repo/|') > "$W/siblings.txt"
build() {
    local src=$1 profile=${2:-}
    mkdir -p "$W/$src-prev"
    find "$TREE/pool/main/${src:0:1}/$src" -maxdepth 1 -name '*+lc1_*.deb' -exec cp --no-preserve=links '{}' "$W/$src-prev/" \;
    index
    disk
    ROUND_SOURCES=$ROUND SPARKY_BUILD_PROFILES=$profile "$DEPTH/build.sh" "$src" "$W/$src-work" "$W/$src-src" "$W/$src-prev" "$TREE" "$ARCHIVE" "$W/new" "$W/siblings.txt"
    cp --no-preserve=links "$W/$src-work/lc"/*.deb "$W/new/"
    index
}
if [ ! -f "$W/layer.done" ]; then
    disk
    SOURCE_NAME=${BUILD_NAME_PREFIX}-source-stereo-layer "$DEPTH/stereo-layer-source.sh" "$FORK" "$REV" "$W/stereo-layer-src"
    build stereo-layer nocheck
    touch "$W/layer.done"
fi
if [ ! -f "$W/dolphin.done" ]; then
    mkdir -p "$W/dolphin-src"
    cp --no-preserve=links "$DOLPHIN"/*.dsc "$DOLPHIN"/*.debian.tar.xz "$DOLPHIN"/*.orig.tar.* "$W/dolphin-src/"
    build dolphin
    touch "$W/dolphin.done"
fi
(cd "$W/new" && sha256sum ./*.deb > SHA256SUMS)
