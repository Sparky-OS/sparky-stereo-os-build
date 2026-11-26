#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/08
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/17
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?Set OUT to the workspace output directory}
VERSION=20261126.2~sparky9~0+lc1
PACKAGE=sparky-stereo-power-profiles
mkdir -p "$OUT"
WORK=$(mktemp -d "$OUT/.power-profiles.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
D=$WORK/$PACKAGE
mkdir -p "$D/DEBIAN" "$D/usr/share/doc/$PACKAGE"
install -Dm644 "$HERE/share/powerdevilrc" "$D/etc/xdg/powerdevilrc"
install -Dm644 "$HERE/share/kscreenlockerrc" "$D/etc/xdg/kscreenlockerrc"
install -Dm755 "$HERE/bin/sparky-stereo-hibernate-check" "$D/usr/libexec/sparky-stereo/hibernate-check"
install -Dm755 "$HERE/share/sparky-stereo-hibernate" "$D/usr/lib/systemd/system-sleep/sparky-stereo-hibernate"
install -Dm644 "$HERE/share/50-sparky-hibernate.conf" "$D/usr/lib/systemd/sleep.conf.d/50-sparky-hibernate.conf"
unit=sparky-stereo-hibernate-capability.service
install -Dm644 "$HERE/share/$unit" "$D/usr/lib/systemd/system/$unit"
sparky-stereo-problems catalog "$PACKAGE" "$HERE/problems-lang" "$D/usr/lib/systemd/catalog" --subject LOCAL1
install -m644 "$HERE/copyright" "$D/usr/share/doc/$PACKAGE/copyright"
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOF
Package: $PACKAGE
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: power-profiles-daemon (>= 0.30), powerdevil (>= 6.7), sparky-stereo-powerdevil-policy (>= 1), sparky-stereo-cushion-swap (>= 0.3.7+lc1), sparky-stereo-problems (>= 0.1.1), python3, systemd, init-system-helpers (>= 1.54~), libkf6config-bin
Breaks: sparky-stereo-problems-plasma (<< 0.2.3)
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: KDE power and idle defaults for Sparky Stereo OS
  Performance on AC, balanced on battery and power saver at low battery.
  Desktop idle keeps the machine awake; plugged laptops sleep after four hours.
  The user's own Plasma settings take precedence.
EOF
printf '%s\n' /etc/xdg/kscreenlockerrc /etc/xdg/powerdevilrc >"$D/DEBIAN/conffiles"
cat >"$D/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
unit=sparky-stereo-hibernate-capability.service
if [ "$1" = configure ]; then
    # dh_installsystemd: keep an administrator's recorded enablement preference.
    deb-systemd-helper unmask "$unit" >/dev/null
    if deb-systemd-helper --quiet was-enabled "$unit"; then
        deb-systemd-helper enable "$unit" >/dev/null
    else
        deb-systemd-helper update-state "$unit" >/dev/null
    fi
    # ORDER 358 keeps activation failures while completing configuration.
    # debhelper 14.5 autoscripts/postinst-systemd-restart uses:
    # systemctl --system daemon-reload >/dev/null || true
    # We show and retain the error; this is not a Policy 6 exception.
    if [ -z "${DPKG_ROOT:-}" ] && [ -d /run/systemd/system ]; then
        sparky-stereo-problems run --machine sparky-stereo-power-profiles daemon-reload LOCAL5 -- systemctl daemon-reload || :
        sparky-stereo-problems run --machine sparky-stereo-power-profiles hibernate-check-start LOCAL5 -- deb-systemd-invoke restart "$unit" || :
    else
        sparky-stereo-problems say sparky-stereo-power-profiles LOCAL6
    fi
fi
EOF
cat >"$D/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = remove ] && [ -z "${DPKG_ROOT:-}" ] && [ -d /run/systemd/system ]; then
    deb-systemd-invoke stop sparky-stereo-hibernate-capability.service >/dev/null || :
fi
EOF
cat >"$D/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
unit=sparky-stereo-hibernate-capability.service
if [ -z "${DPKG_ROOT:-}" ] && [ -d /run/systemd/system ]; then
    systemctl --system daemon-reload >/dev/null || :
fi
if [ "$1" = remove ] && command -v deb-systemd-helper >/dev/null; then
    deb-systemd-helper mask "$unit" >/dev/null || :
fi
if [ "$1" = purge ] && command -v deb-systemd-helper >/dev/null; then
    deb-systemd-helper purge "$unit" >/dev/null || :
    deb-systemd-helper unmask "$unit" >/dev/null || :
fi
if [ "$1" = remove ] && [ -z "${DPKG_ROOT:-}" ] && command -v sparky-stereo-problems >/dev/null 2>&1; then
    sparky-stereo-problems clear --all sparky-stereo-power-profiles
fi
EOF
chmod 755 "$D/DEBIAN/postinst" "$D/DEBIAN/prerm" "$D/DEBIAN/postrm"
(cd "$D" && find etc usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums)
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone "$D" "$OUT" --authoring "$HERE" --build-dependency sparky-stereo-problems
