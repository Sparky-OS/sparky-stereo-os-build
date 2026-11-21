#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/21
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: the two upstream tarballs of Ollama 0.40.16+ds, made from the inputs release.tsv pins.
#   ollama_V.orig.tar.xz           the tag's source (tarball SHA-256, the commit its pax header names, the git tree id of its files)
#   ollama_V.orig-release.tar.xz   upstream's Linux amd64 and ROCm bundles, checked by size and SHA-256, without the files listed in
#                                  release/EXCLUDED.tsv (each with its size, SHA-256 and reason), with AMD's licence texts and a
#                                  MANIFEST.sha256 of everything kept
# The release has no signature for its Linux bundles: the check is the pinned size and SHA-256, compared with the release's own
# sha256sum.txt, which comes from the same origin as the files.
# Usage: make-orig.sh DOWNLOADS OUT   (DOWNLOADS keeps the inputs between runs; a missing input is fetched over https only)
set -euo pipefail
umask 022
HERE=$(cd "$(dirname "$0")" && pwd)
DL=$(realpath -m "${1:?downloads folder}")
OUT=$(realpath -m "${2:?output folder}")
UPV=0.40.16
V=$UPV+ds
COMMIT=d63b702609c4300a2ca07be2bdb0adb9834725e5
TREE=5d6b350951162c38b342985c12ebd10e7522dfeb
mkdir -p "$DL" "$OUT"
[ -z "$(ls -A "$OUT")" ] || { echo "$OUT is not empty" >&2; exit 1; }
WORK=$(mktemp -d "$OUT/.work.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

while IFS=$'\t' read -r name bytes sha url; do
	case $name in ''|'#'*) continue ;; esac
	file=$DL/$name
	mkdir -p "$(dirname "$file")"
	if [ ! -f "$file" ]; then
		curl --proto =https --tlsv1.2 -fsSL --retry 3 -o "$file.part" "$url"
		mv "$file.part" "$file"
	fi
	if [ "$bytes" != - ] && [ "$(stat -c %s "$file")" != "$bytes" ]; then
		echo "$name is $(stat -c %s "$file") bytes, not the pinned $bytes" >&2; exit 1
	fi
	got=$(sha256sum "$file" | cut -d' ' -f1)
	[ "$got" = "$sha" ] || { echo "$name has SHA-256 $got, not the pinned $sha" >&2; exit 1; }
done < "$HERE/release.tsv"
for b in ollama-linux-amd64.tar.zst ollama-linux-amd64-rocm.tar.zst; do
	listed=$(awk -v f="./$b" '$2 == f {print $1}' "$DL/sha256sum.txt")
	[ "$listed" = "$(sha256sum "$DL/$b" | cut -d' ' -f1)" ] || { echo "$b is not what the release's sha256sum.txt lists" >&2; exit 1; }
done
echo "inputs: every file matches its pinned size and SHA-256; both bundles match the release's sha256sum.txt"

# the source: the commit the tarball says it is, and exactly that commit's files
pax=$(python3 -I -c 'import sys, tarfile; print(tarfile.open(sys.argv[1]).pax_headers.get("comment", ""))' "$DL/ollama-$UPV-src.tar.gz")
[ "$pax" = "$COMMIT" ] || { echo "the source tarball names commit '$pax', not $COMMIT" >&2; exit 1; }
mkdir "$WORK/src"
tar -xzf "$DL/ollama-$UPV-src.tar.gz" -C "$WORK/src"
git init -q --bare "$WORK/idx.git"
got=$(cd "$WORK/src/ollama-$UPV" && GIT_DIR=$WORK/idx.git GIT_WORK_TREE=. git add -A -f && GIT_DIR=$WORK/idx.git git write-tree)
[ "$got" = "$TREE" ] || { echo "the source's git tree is $got, not the tag's $TREE" >&2; exit 1; }
# the tag commit's time (2026-11-08T00:36:53Z), so the same inputs give the same bytes
EPOCH=1794098213
mv "$WORK/src/ollama-$UPV" "$WORK/src/ollama-$V"
tar --sort=name --format=gnu --mtime="@$EPOCH" --owner=0 --group=0 --numeric-owner -C "$WORK/src" -cf - "ollama-$V" | xz -6 -T4 > "$OUT/ollama_$V.orig.tar.xz"
echo "source: commit $COMMIT, tree $TREE"

# the release payload
R=$WORK/release
mkdir -p "$R/payload" "$R/licences/rocm"
zstd -dc "$DL/ollama-linux-amd64.tar.zst" | tar -xf - -C "$R/payload"
zstd -dc "$DL/ollama-linux-amd64-rocm.tar.zst" | tar -xf - -C "$R/payload"
cp "$DL"/licences/rocm/*.txt "$R/licences/rocm/"
python3 -I - "$R" <<'PY'
import hashlib, os, re, sys
root = sys.argv[1]
payload = os.path.join(root, 'payload')
nvidia = re.compile(r'^lib/ollama/cuda_v13/lib(cudart|cublas|cublasLt|nvrtc|nvrtc-builtins|nvJitLink|nvfatbin)\.so')
rules = [
    (lambda p: p.startswith('lib/ollama/cuda_v12/'),
     "the CUDA 12 runner: NVIDIA's CUDA 12 runtime (libcudart.so.12) has no package in NVIDIA's repository for Debian 13 nor in Debian, so this runner could not load"),
    (lambda p: bool(nvidia.match(p)),
     "NVIDIA's CUDA library: the CUDA EULA lets an application's developer distribute it, so it comes from NVIDIA's repository on the person's machine (ollama-cuda depends on it)"),
    (lambda p: p.startswith('lib/ollama/libgomp.so'),
     "GCC's OpenMP library: no file of the bundle links it"),
    (lambda p: re.match(r'^lib/ollama/rocm_v7_2/lib(drm|drm_amdgpu|numa|elf)[-.]', p) is not None,
     "a general library Debian ships (libdrm2, libdrm-amdgpu1, libnuma1, libelf1t64); ollama-rocm depends on Debian's"),
]
excluded, kept = [], []
for base, dirs, files in os.walk(payload):
    dirs.sort()
    for name in sorted(files):
        full = os.path.join(base, name)
        rel = os.path.relpath(full, payload)
        why = next((w for test, w in rules if test(rel)), None)
        if os.path.islink(full):
            size, digest = 0, 'symlink:' + os.readlink(full)
        else:
            size = os.path.getsize(full)
            with open(full, 'rb') as f:
                digest = hashlib.file_digest(f, 'sha256').hexdigest()
        if why:
            excluded.append((rel, size, digest, why))
            os.unlink(full)
        else:
            kept.append((rel, digest))
for base, dirs, files in os.walk(payload, topdown=False):
    if base != payload and not os.listdir(base):
        os.rmdir(base)
with open(os.path.join(root, 'EXCLUDED.tsv'), 'w') as f:
    f.write('# path\tbytes\tsha256 (or symlink target)\twhy it is not in this package\n')
    for row in excluded:
        f.write('\t'.join(map(str, row)) + '\n')
with open(os.path.join(root, 'MANIFEST.sha256'), 'w') as f:
    for rel, digest in kept:
        if not digest.startswith('symlink:'):
            f.write(f'{digest}  payload/{rel}\n')
print(f'release: {len(kept)} files kept, {len(excluded)} left out ({sum(r[1] for r in excluded):,} bytes); see EXCLUDED.tsv')
PY
tar --sort=name --format=gnu --mtime="@$EPOCH" --owner=0 --group=0 --numeric-owner -C "$WORK" -cf - release | xz -6 -T4 > "$OUT/ollama_$V.orig-release.tar.xz"
(cd "$OUT" && sha256sum ollama_$V.orig.tar.xz ollama_$V.orig-release.tar.xz)
