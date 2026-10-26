#!/bin/sh
# Resolve the rootfs recipe without installing packages. Run in an isolated build image.
# Keep OUT and the image's apt indexes for a reproducible before/after comparison.
# SKIP_APT_SETUP=1 reuses frozen sources/indexes; STATUS can name a minbase dpkg status.
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
if [ "${SKIP_APT_SETUP:-0}" != 1 ]; then
	"$HERE/apt-setup.sh" /
	apt-get update -o APT::Update::Error-Mode=any
fi
: "${OUT:?Set OUT to a new directory for the probe results}"
"$HERE/base-list.sh" > "$OUT.base.names"
[ -s "$OUT.base.names" ] || { echo 'size-probe: empty base list' >&2; exit 1; }
exec python3 "$HERE/simulate-image.py" --base "$OUT.base.names" \
	--recipe "${RECIPE:-$HERE/rootfs.sh}" --status "${STATUS:-/var/lib/dpkg/status}" \
	--allow-remove "${REMOVE:-/edition-lists/base-remove.list}" --out "$OUT"
