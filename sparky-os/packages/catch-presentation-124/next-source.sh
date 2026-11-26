#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
toolkit=$(cd -- "$here/../.." && pwd)
base=$(realpath -e "${1:?Usage: next-source.sh ROW927_STAGE OUT}")
out=${2:?Usage: next-source.sh ROW927_STAGE OUT}
dsc="$base/krdc_26.04.0-1+stereo3d4+lc1.dsc"
printf '%s  %s\n' f08917160ba9327dc21d56a1c190a56a4372a31bccaf084e22d8d336aa695fc9 "$dsc" |
    sha256sum --strict --check
work=$(mktemp -d "${TMPDIR:-/tmp}/catch-124.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
dpkg-source --skip-patches -x "$dsc" "$work/base"
overlay="$work/overlay"
mkdir -p "$overlay/patches"
cp "$work/base/debian/patches/series" "$overlay/patches/series"
cp "$work/base/debian/copyright" "$overlay/copyright"
if [[ -f "$work/base/debian/sparky-provenance-files" ]]; then
    cp "$work/base/debian/sparky-provenance-files" "$overlay/"
fi
for patch in "$here/krdc-order124e.patch" "$toolkit/translations/krdc-order124e.po.patch"; do
    filename=${patch##*/}
    cp "$patch" "$overlay/patches/"
    printf '%s\n' "$filename" >> "$overlay/patches/series"
    printf 'debian/patches/%s\n' "$filename" >> "$overlay/sparky-provenance-files"
done
cat >> "$overlay/copyright" <<'COPYRIGHT'

Files: rdp/catch/presentation.* rdp/catch/waitingscenes.* rdp/catch/optics/Viewer/*
Copyright: 2026 Daniel Campos Ramos
License: GPL-3+
 On Debian systems the complete text of the GNU General Public License
 version 3 can be found in /usr/share/common-licenses/GPL-3.

Files: rdp/catch/optics/ThirdParty/Cardboard/*
Copyright: 2019-2021 Google LLC
License: Apache-2.0
 On Debian systems the complete text of the Apache License
 version 2.0 can be found in /usr/share/common-licenses/Apache-2.0.
COPYRIGHT
dependency=$'               libkscreen-dev,\n               libavcodec-dev,\n               libavformat-dev,\n               libavutil-dev,\n               libswscale-dev,\n               zlib1g-dev'
python3 "$toolkit/repo/lc-successor.py" --in-place --reapply-patches \
    --next '4:26.04.0-1+stereo3d5' \
    --item 'Carry the Flat Headset lens profiles, guide and waiting scenes into Catch (row 124).' \
    --depends "               libkscreen-dev" "$dependency" \
    --overlay "$overlay" --source-date-epoch "${SOURCE_DATE_EPOCH:?Build clock is required}" \
    --work "$work" "$dsc" "$out"
