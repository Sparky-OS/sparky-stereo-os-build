#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
toolkit=$(cd -- "$here/../.." && pwd)
base=$(realpath -e "${1:?Usage: next-source.sh KRDP_OR_KRDC_BASE_DIR OUT}")
out=${2:?Usage: next-source.sh KRDP_OR_KRDC_BASE_DIR OUT}
case "${SOURCE:?Set SOURCE to krdp or krdc}" in
    krdp)
        dsc="$base/krdp_6.7.4-1+stereo3d11.dsc"
        sha=34ee34753042f6687a05e9d63e2e036e206b13c64295db32b27aaf254daf32a7
        version=6.7.4-1+stereo3d12
        patches=("$here/patches/catch-no-picture.patch")
        ;;
    krdc)
        dsc="$base/krdc_26.04.0-1+stereo3d3+lc1.dsc"
        sha=fbb19bbe0039fd441f871cece59d2b9abf354d6433f83ccbc291fbef2b0cc747
        version=4:26.04.0-1+stereo3d4
        patches=("$toolkit/packages/catalogue-rebuilds/patches/krdc-order124d.patch"
                 "$toolkit/translations/krdc-order124d.po.patch")
        ;;
    *) exit 2 ;;
esac
printf '%s  %s\n' "$sha" "$dsc" | sha256sum --strict --check
work=$(mktemp -d "${TMPDIR:-/tmp}/catch-927.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
dpkg-source --skip-patches -x "$dsc" "$work/base"
overlay="$work/overlay"
mkdir -p "$overlay/patches"
cp "$work/base/debian/patches/series" "$overlay/patches/series"
if [[ -f "$work/base/debian/sparky-provenance-files" ]]; then
    cp "$work/base/debian/sparky-provenance-files" "$overlay/"
fi
for patch in "${patches[@]}"; do
    filename=${patch##*/}
    cp "$patch" "$overlay/patches/"
    printf '%s\n' "$filename" >> "$overlay/patches/series"
    printf 'debian/patches/%s\n' "$filename" >> "$overlay/sparky-provenance-files"
done
python3 "$toolkit/repo/lc-successor.py" --in-place --reapply-patches --next "$version" \
    --item 'Tell the person when an approved Throw delivers no picture (row 927).' \
    --overlay "$overlay" --source-date-epoch "${SOURCE_DATE_EPOCH:?Build clock is required}" \
    --work "$work" "$dsc" "$out"
