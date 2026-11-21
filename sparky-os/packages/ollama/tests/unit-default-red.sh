#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/21
# Copyright 2026 under the GNU GPL3 License
# The red control of unit-off.sh: a throwaway package with ollama's own user unit, built with debhelper's default
# dh_installsystemduser (no --no-enable), installed in the same kind of container. Expected: "enabled".
# Usage (root, in a Debian testing container with debhelper): unit-default-red.sh UNIT-FILE
set -eu
unit=${1:?the ollama.user.service of the recipe}
w=$(mktemp -d)
mkdir -p "$w/red/debian/source"
cp "$unit" "$w/red/debian/unit-default-red.user.service"
echo '3.0 (native)' > "$w/red/debian/source/format"
printf 'Source: unit-default-red\nSection: misc\nPriority: optional\nMaintainer: Test <test@invalid>\nBuild-Depends: debhelper-compat (= 14)\nStandards-Version: 4.7.2\nRules-Requires-Root: no\n\nPackage: unit-default-red\nArchitecture: all\nDepends: ${misc:Depends}\nDescription: red control\n the unit with the default dh_installsystemduser\n' > "$w/red/debian/control"
printf 'unit-default-red (1) unstable; urgency=medium\n\n  * test\n\n -- Test <test@invalid>  Sat, 21 Nov 2026 00:00:00 +0000\n' > "$w/red/debian/changelog"
printf '#!/usr/bin/make -f\n%%:\n\tdh $@ --buildsystem=none\n' > "$w/red/debian/rules"
chmod +x "$w/red/debian/rules"
(cd "$w/red" && dpkg-buildpackage -us -uc -b -d >/dev/null 2>&1)
dpkg -i "$w"/unit-default-red_1_all.deb >/dev/null
state=$(systemctl --global is-enabled unit-default-red.service 2>&1)
echo "red control, debhelper's default: systemctl --global is-enabled unit-default-red.service: $state"
grep -c 'deb-systemd-helper --user' /var/lib/dpkg/info/unit-default-red.postinst | sed 's/^/deb-systemd-helper --user lines in its postinst: /'
[ "$state" = enabled ]
