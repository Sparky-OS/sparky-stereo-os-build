#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Runs as the build user in a disposable testing container.
set -euo pipefail
: "${SOURCE_DATE_EPOCH:?recipe date}" "${SOURCE_DATE_RFC2822:?recipe date}"
name=${1:?source name}
HERE=$(cd "$(dirname "$0")" && pwd)
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL='Capitain_Jack@yahoo.com'
export PYTHONPATH=/toolkit
case $name in
hplip)
 dsc=hplip_3.26.4+dfsg0-4.dsc
 sha=ee8e0e713a7020ae102ae07e6bc43aef4d730dedf9556de54a0754b783760425
 patch=hplip-3.26.6-security.patch
 version=3.26.4+dfsg0-4+stereo3d1+lc1
 entry="Carry Debian unstable's HP printing and scanning with HP 3.26.6 security remediation (CVE-2026-91097 through CVE-2026-91106); retain Debian packaging and credit HP."
 ;;
xserver-xorg-video-qxl)
 dsc=xserver-xorg-video-qxl_0.1.6-1.1.dsc
 sha=a176db700fa9426cbf6a7eea2b2f1f0d816ed0f845e5ca2e19c0bcc01043a3fd
 patch=qxl-default-options.patch
 version=0.1.6-1.1+stereo3d1+lc1
 entry="Carry Debian unstable's QXL and Xspice; apply Frank Heckenbach's option-default fix from Debian bug 1137518."
 ;;
*) echo "no qualified preparation for $name" >&2; exit 2 ;;
esac
mkdir -p "/work/candidates/$name"
cd "/work/candidates/$name"
[ ! -e source ] || { echo 'source already exists' >&2; exit 1; }
printf '%s  %s\n' "$sha" "/work/$name/$dsc" | sha256sum -c -
cp /work/"$name"/*.orig.tar.* .
dpkg-source -x "/work/$name/$dsc" source
cd source
cp "$HERE/patches/$patch" "debian/patches/$patch"
printf '%s\n' "$patch" >> debian/patches/series
QUILT_PATCHES=debian/patches quilt push
if [ "$name" = hplip ]; then
 # HP removed the privileged plugin D-Bus service in its security release.
 sed -i '/^usr\/bin\/hp-pkservice$/d; /^usr\/share\/polkit-1$/d; /^usr\/share\/dbus-1$/d' debian/hplip.install
fi
python3 - <<'PY'
from pathlib import Path
import re
p=Path('debian/control');s=p.read_text()
s=re.sub(r'^Maintainer: (.*)$',r'Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>\nXSBC-Original-Maintainer: \1',s,count=1,flags=re.M)
p.write_text(s)
PY
python3 -m lean.debian_prepare . "$version" --toolkit /toolkit
dch --date "$SOURCE_DATE_RFC2822" --append "$entry"
python3 /toolkit/repo/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" .
dpkg-buildpackage -S -d -us -uc -sa
