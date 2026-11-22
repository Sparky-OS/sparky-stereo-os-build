#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
# Build one unmodified release using the edition's source preparation and gates.
# All downloads and dependency installation precede this offline build.
# Usage: build.sh captiond|kaption OUT ORIG IMAGE ARCHIVE REPO SIBLINGS
set -euo pipefail
name=${1:?captiond or kaption}
case "$name" in captiond|kaption) ;; *) exit 2;; esac
out=$(realpath -m "${2:?new output folder}")
orig=$(realpath "${3:?release tarball}")
image=${4:?prepared build image}
archive=$(realpath "${5:?offline archive folder}")
repo=$(realpath "${6:?published edition repository}")
siblings=$(realpath "${7:?edition sibling list using /repo paths}")
here=$(cd "$(dirname "$0")" && pwd)
toolkit=$(realpath "$here/../..")
source "$toolkit/repo/build-provenance.sh"
[ ! -e "$out" ] || { echo "Output already exists: $out" >&2; exit 2; }
mkdir -p "$out"
python3 - "$here/../$name/upstream.json" "$orig" <<'PY'
import hashlib,json,sys
from pathlib import Path
record=json.loads(Path(sys.argv[1]).read_text()); data=Path(sys.argv[2]).read_bytes()
assert len(data)==record['bytes'] and hashlib.sha256(data).hexdigest()==record['sha256']
PY
cp "$orig" "$out/${name}_0.1.0.orig.tar.xz"
tar -xJf "$orig" -C "$out"
cp -a "$here/../$name/debian" "$out/$name-0.1.0/"
SOURCE_DATE_EPOCH=$(python3 "$toolkit/repo/reproducible.py" changelog "$out/$name-0.1.0/debian/changelog")
export SOURCE_DATE_EPOCH SPARKY_SOURCE_DATE_BASIS="newest $name packaging changelog"
export SPARKY_PROVENANCE_REQUIRED=1
sparky_provenance_init "$image" "$here/../$name"
[ "${SPARKY_BUILD_DIRTY:-0}" = 0 ] # init also records dirty state in SPARKY_PROV_ARGS
[ -z "$(git -C "$toolkit/.." status --porcelain -- sparky-os)" ] || { echo 'Commit recipes first' >&2; exit 2; }
container="${SPARKY_CONTAINER_PREFIX:-lc73}-build-$name"
docker create --name "$container" --pull=never --platform linux/amd64 --cpus 4 --ulimit core=1 --network none \
 --security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
 "${SPARKY_PROV_ARGS[@]}" \
 --mount type=bind,source="$out",target=/work \
 --mount type=bind,source="$toolkit",target=/toolkit,readonly \
 --mount type=bind,source="$archive",target=/archive,readonly \
 --mount type=bind,source="$repo",target=/repo,readonly \
 --mount type=bind,source="$siblings",target=/siblings.txt,readonly \
 -e NAME="$name" -e OWNER="$(id -u):$(id -g)" \
 -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch \
 -e SPARKY_LC_SIBLINGS_FILE=/siblings.txt -e SPARKY_LC_MIN_FREE_GIB=2 -e SPARKY_LC_ROOT_MIN_FREE_GIB=1 \
 "$image" bash -c '
set -euo pipefail
export DEBFULLNAME="Daniel Ramos (Capitain Jack)" DEBEMAIL=Capitain_Jack@yahoo.com
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
chown -R builder:builder /work
cd /work
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" "/work/$NAME-0.1.0"
runuser -u builder -- dpkg-source -b "$NAME-0.1.0"
mkdir authored
cp ./*.dsc ./*.debian.tar.xz ./*.orig.tar.xz authored/
runuser -u builder -- dpkg-source -x "${NAME}_0.1.0-1.dsc" lean-source
runuser -u builder -- env PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lean-source 0.1.0-1+lc1 --toolkit /toolkit
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" /work/lean-source
cd /work/lean-source
runuser -u builder -- dpkg-checkbuilddeps
cat /proc/loadavg > /work/load-before.txt
runuser -u builder -- dpkg-buildpackage -us -uc -j4
cat /proc/loadavg > /work/load-after.txt
cd /work
PYTHONPATH=/toolkit python3 -m lean.release check-debs ./*+lc1_*.deb
cp lean-source/.sparky-lc/source.json native-source.json
chown -R "$OWNER" /work
' > "$out/container-id.txt"
docker inspect -f '{{.Id}}' "$container" >> "${LANE_CONTAINER_IDS:-$out/.container-ids}"
# Preserve a failed container for diagnosis; the caller records and removes it.
docker start -a "$container" > "$out/build.log" 2>&1
test "$(docker inspect -f '{{.State.ExitCode}}' "$container")" = 0
