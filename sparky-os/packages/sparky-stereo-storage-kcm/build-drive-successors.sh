#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Prepare the source closures from the verified edition pool.
set -eu
: "${SOURCE_DATE_EPOCH:?}" "${OUT:?}"
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
packages=$(dirname -- "$here")
toolkit=$(dirname -- "$packages")
pool=$(realpath "${1:?Supply the edition pool/main directory}")
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT HUP INT TERM
export DEBEMAIL=Capitain_Jack@yahoo.com DEBFULLNAME='Daniel Ramos (Capitain Jack)'

successor()
{
    name=$1 dsc=$2 version=$3 patch_file=$4 item=$5
    mkdir -p "$work/$name/overlay/patches" "$OUT/$name"
    dpkg-source -x "$dsc" "$work/$name/base"
    cp -- "$work/$name/base/debian/patches/series" "$work/$name/overlay/patches/"
    cp -- "$patch_file" "$work/$name/overlay/patches/"
    printf '%s\n' "$(basename -- "$patch_file")" >> "$work/$name/overlay/patches/series"
    python3 "$toolkit/repo/lc-successor.py" --in-place --reapply-patches \
        --overlay "$work/$name/overlay" --next "$version" --item "$item" "$dsc" "$OUT/$name"
    for file in "$(dirname -- "$dsc")/${name}_"*.orig*; do
        cp -- "$file" "$OUT/$name/"
    done
}

successor dolphin "$pool/d/dolphin/dolphin_26.08.0-1+stereo3d8+lc1.dsc" \
    4:26.08.0-1+stereo3d10 "$packages/dolphin/storage-cleanup.patch" \
    'Open Storage Cleanup from a mounted device in the Places menu.'
successor plasma-workspace "$pool/p/plasma-workspace/plasma-workspace_6.7.4-2+stereo3d10+lc1.dsc" \
    4:6.7.4-2+stereo3d12 "$packages/plasma-workspace/patches/s12-0001-freespacenotifier-hand-low-space-to-Problems.patch" \
    'Offer drive-scoped Storage Cleanup through Problems at the existing low-space threshold.'
