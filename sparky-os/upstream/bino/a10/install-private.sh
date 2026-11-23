#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
export LC_ALL=C.UTF-8
cd -- "$(dirname -- "$0")"
test "$(id -u)" != 0 || { echo 'Run as the desktop user, without sudo.' >&2; exit 1; }
sha256sum -c SHA256SUMS
check_version() {
	local package=$1 minimum=$2 actual
	actual=$(dpkg-query -W -f='${Version}' "$package")
	dpkg --compare-versions "$actual" ge "$minimum" || { echo "$package $minimum or newer is required (found $actual)." >&2; exit 1; }
}
check_version kwin-wayland '4:6.7.4-2+stereo3d34+lc1'
check_version libstereo-declare1 '1.6.0-1+lc1'
check_version libstereo-layer1 '1.10.0-1+lc1'
check_version libqt6multimedia6 '6.11.2-3+stereo3d9+lc1'
dpkg-query -W -f='${Provides}' libqt6multimedia6 | grep -F 'qt6-multimedia-private-abi (= 6.11.2)' >/dev/null || { echo 'Qt Multimedia private ABI 6.11.2 is required.' >&2; exit 1; }
test "$(dpkg-query -W -f='${db:Status-Status}' qt6-svg-plugins)" = installed || { echo 'The published qt6-svg-plugins package is required.' >&2; exit 1; }
for tool in kde-inhibit qdbus6 kscreen-doctor ffprobe python3; do
	command -v "$tool" >/dev/null || { echo "Missing runtime tool: $tool" >&2; exit 1; }
done
test ! -e private || { echo 'The private prefix already exists; preserve or remove it explicitly before reinstalling.' >&2; exit 1; }
mkdir private
for variant in published candidate; do
	version=2.8-1+stereo3d2+lc1
	test "$variant" != candidate || version=2.8-1+stereo3d3+lc1
	deb="packages/bino_${version}_amd64.deb"
	test "$(dpkg-deb -f "$deb" Version)" = "$version"
	dpkg-deb -x "$deb" "private/$variant"
	ldd -r "private/$variant/usr/bin/bino" > "private/$variant-link.txt" 2>&1
	if grep -E 'not found|undefined symbol' "private/$variant-link.txt"; then
		echo 'Published runtime dependencies are missing; no system package was changed.' >&2
		exit 1
	fi
	QT_QPA_PLATFORM=offscreen LD_BIND_NOW=1 "private/$variant/usr/bin/bino" --help > "private/$variant-help.txt" 2>&1
done
echo 'Both Bino versions are extracted under private/. The installed Bino is unchanged.'
echo 'To restore the original state, stop the bench and remove this kit directory.'
