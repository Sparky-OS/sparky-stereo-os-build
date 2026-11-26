#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
toolkit=$(cd -- "$here/../.." && pwd)
base=$(realpath -e "${1:?Usage: next-source.sh BASE_DIR OUT}")
out=${2:?Usage: next-source.sh BASE_DIR OUT}
dsc="$base/kpipewire_6.7.4-1+stereo3d10.dsc"
sha=67f8161e2285bbe7e56c4eb786077ed2d831c17cd0832aa41ef5dc6c29e0e092
printf '%s  %s\n' "$sha" "$dsc" | sha256sum --strict --check
version=6.7.4-1+stereo3d11
work=$(mktemp -d "${TMPDIR:-/tmp}/kpipewire-927.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
dpkg-source --skip-patches -x "$dsc" "$work/base"
overlay="$work/overlay"
mkdir -p "$overlay/patches"
cp "$work/base/debian/patches/series" "$overlay/patches/series"
patch=size-pipewire-format-params.patch
cp "$here/patches/$patch" "$overlay/patches/"
printf '%s\n' "$patch" >> "$overlay/patches/series"
cp "$work/base/debian/sparky-provenance-files" "$overlay/"
printf 'debian/patches/%s\n' "$patch" >> "$overlay/sparky-provenance-files"

# The changed function is private in the exported class. The public ABI is unchanged.
symbols=libkpipewire6.symbols
sed "s/_ZN20PipeWireSourceStream19createFormatsParamsE15spa_pod_builder@Base 6.1.0/_ZN20PipeWireSourceStream19createFormatsParamsER10QByteArray@Base $version/" \
    "$work/base/debian/$symbols" > "$overlay/$symbols"
export DEBFULLNAME='Daniel Campos Ramos' DEBEMAIL=Capitain_Jack@yahoo.com
python3 "$toolkit/repo/lc-successor.py" --in-place --reapply-patches --next "$version" \
    --item "$(tr '\n' ' ' < "$here/changelog/kpipewire.items")" --overlay "$overlay" \
    --source-date-epoch "${SOURCE_DATE_EPOCH:?Build clock is required}" --work "$work" "$dsc" "$out"
