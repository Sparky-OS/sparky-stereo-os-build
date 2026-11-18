#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
python3 "$HERE/tests/test_system_language.py"
OUT=${OUT:?}
VERSION=1.0.8+lc1
TASKSEL_SOURCE_DIR=${TASKSEL_SOURCE_DIR:?Set TASKSEL_SOURCE_DIR to Debian tasksel 3.92 descriptor and source archive}
WORK=$(mktemp -d "${BUILD_ROOT:?}/language-tasks.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
D=$WORK/tree
P=sparky-stereo-language-tasks
mkdir -p "$D/DEBIAN" "$D/usr/lib/$P" "$D/usr/share/$P" "$D/usr/share/doc/$P" "$D/usr/lib/systemd/system"
install -m755 "$HERE/bin/languages" "$D/usr/lib/$P/languages"
install -Dm755 "$HERE/bin/tasksel-test" "$D/usr/lib/tasksel/tests/sparky-language"
install -m644 "$HERE/../../lists/language-tasks.json" "$D/usr/share/$P/manifest.json"
install -m644 "$HERE/systemd/"* "$D/usr/lib/systemd/system/"
install -m644 "$HERE/copyright" "$D/usr/share/doc/$P/copyright"
gzip -9n -c "$HERE/CHANGELOG" > "$D/usr/share/doc/$P/changelog.gz"
python3 "$HERE/catalogues.py" --source-dir "$TASKSEL_SOURCE_DIR" --tree "$D"
cat > "$D/DEBIAN/preinst" <<'EOF'
#!/bin/sh
set -e
for l in en pl pt_BR fr de es ja ko zh_CN zh_TW; do
    f=/usr/share/locale/$l/LC_MESSAGES/debian-tasks.mo
    dpkg-divert --package sparky-stereo-language-tasks --rename --divert "$f.debian-language-tasks" --add "$f"
done
EOF
cat > "$D/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = configure ]; then
    for l in en pl pt_BR fr de es ja ko zh_CN zh_TW; do
        f=/usr/share/locale/$l/LC_MESSAGES/debian-tasks.mo
        target=/usr/share/sparky-stereo-language-tasks/tasksel/$l/debian-tasks.mo
        mkdir -p "$(dirname "$f")"
        if [ "$(readlink "$f" 2>/dev/null || :)" != "$target" ]; then ln -s "$target" "$f"; fi
    done
    /usr/lib/sparky-stereo-language-tasks/languages queue
    sparky-stereo-problems catalog sparky-stereo-language-tasks /usr/share/sparky/sparky-stereo-language-tasks /usr/lib/systemd/catalog --subject LOCAL1
    systemctl enable sparky-stereo-language-tasks.path sparky-stereo-language-tasks.service
    if [ -d /run/systemd/system ]; then
        systemctl daemon-reload
        systemctl --no-block start sparky-stereo-language-tasks.path sparky-stereo-language-tasks.service
    fi
fi
EOF
cat > "$D/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = remove ] || [ "$1" = purge ]; then
    for l in en pl pt_BR fr de es ja ko zh_CN zh_TW; do
        f=/usr/share/locale/$l/LC_MESSAGES/debian-tasks.mo
        target=/usr/share/sparky-stereo-language-tasks/tasksel/$l/debian-tasks.mo
        if [ "$(readlink "$f" 2>/dev/null || :)" = "$target" ]; then rm "$f"; fi
        dpkg-divert --package sparky-stereo-language-tasks --rename --divert "$f.debian-language-tasks" --remove "$f"
    done
fi
EOF
chmod 755 "$D/DEBIAN/"{preinst,postinst,postrm}
mkdir -p "$D/etc/apt/apt.conf.d"
cat > "$D/etc/apt/apt.conf.d/90sparky-language-retry" <<'EOF'
DPkg::Post-Invoke { "test ! -x /usr/lib/sparky-stereo-language-tasks/languages || /usr/lib/sparky-stereo-language-tasks/languages retry"; };
EOF
printf '/etc/apt/apt.conf.d/90sparky-language-retry\n' > "$D/DEBIAN/conffiles"
cat > "$D/DEBIAN/control" <<EOF
Package: $P
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Depends: python3, dash, base-files, apt, dpkg, tasksel, systemd, sparky-stereo-problems
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: Shared language support
 Shared fonts, locales and input methods.
EOF
PYTHONPATH="$HERE/../.." python3 -m lean.standalone "$D" "$OUT" --authoring "$HERE" --build-dependency gettext
python3 "$HERE/retain-source.py" "$OUT" "$TASKSEL_SOURCE_DIR" "$VERSION"
