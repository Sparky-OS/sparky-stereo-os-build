#!/bin/sh
# Resolve the rootfs recipe without installing packages. Run in an isolated build image.
# Keep OUT and the image's apt indexes for a reproducible before/after comparison.
# SKIP_APT_SETUP=1 reuses frozen sources/indexes; STATUS can name a minbase dpkg status.
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
if [ "${SKIP_APT_SETUP:-0}" != 1 ]; then
	"$HERE/apt-setup.sh" /
	apt-get update -o APT::Update::Error-Mode=any
	# NVIDIA's CUDA repository as the image has it: the source and key of sparky-stereo-cuda-repo, which rootfs.sh installs
	# with the driver lock before any other package (simulate-image.py applies both packages' pins after that install)
	W=$(mktemp -d)
	(cd "$W" && apt-get download -qq sparky-stereo-cuda-repo)
	# its postinst writes the source from the package's copy when no other source names the repository, as in the image
	dpkg-deb --fsys-tarfile "$W"/sparky-stereo-cuda-repo_*_all.deb | tar -x -C / ./usr/share/keyrings/cuda-archive-keyring.gpg
	dpkg-deb --fsys-tarfile "$W"/sparky-stereo-cuda-repo_*_all.deb |
		tar -xO ./usr/share/sparky-stereo-cuda-repo/sparky-stereo-cuda.sources >/etc/apt/sources.list.d/sparky-stereo-cuda.sources
	rm -rf "$W"
	apt-get update -o APT::Update::Error-Mode=any
fi
: "${OUT:?Set OUT to a new directory for the probe results}"
"$HERE/base-list.sh" > "$OUT.base.names"
[ -s "$OUT.base.names" ] || { echo 'size-probe: empty base list' >&2; exit 1; }
exec python3 "$HERE/simulate-image.py" --base "$OUT.base.names" \
	--recipe "${RECIPE:-$HERE/rootfs.sh}" --status "${STATUS:-/var/lib/dpkg/status}" \
	--allow-remove "${REMOVE:-/edition-lists/base-remove.list}" --out "$OUT"
