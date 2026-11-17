#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?}
VERSION=1.0.2+lc1
WORK=$(mktemp -d "${BUILD_ROOT:?}/language-tasks.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
D=$WORK/tree
P=sparky-stereo-language-tasks
mkdir -p "$D/DEBIAN" "$D/usr/lib/$P" "$D/usr/share/$P" "$D/usr/share/doc/$P" "$D/usr/lib/systemd/system"
install -m755 "$HERE/bin/languages" "$D/usr/lib/$P/languages"
install -m644 "$HERE/../../lists/language-tasks.json" "$D/usr/share/$P/manifest.json"
install -m644 "$HERE/systemd/"* "$D/usr/lib/systemd/system/"
install -m644 "$HERE/copyright" "$D/usr/share/doc/$P/copyright"
for po in "$HERE"/po/*.po; do
    lang=$(basename "$po" .po)
    dest=$D/usr/share/locale/$lang/LC_MESSAGES
    mkdir -p "$dest"
    msgfmt --check-format -o "$dest/$P.mo" "$po"
    merged=$D/usr/share/$P/tasksel/$lang
    mkdir -p "$merged"
    # tasksel uses the debian-tasks domain; retain upstream messages alongside ours.
    if [ -f "$HERE/upstream-po/$lang.po" ]; then
        msgcat --use-first "$po" "$HERE/upstream-po/$lang.po" -o "$WORK/merged.po"
        msgfmt --check-format -o "$merged/debian-tasks.mo" "$WORK/merged.po"
    else
        cp "$dest/$P.mo" "$merged/debian-tasks.mo"
    fi
done
python3 - "$D" <<'PYCODE'
import gettext, json, pathlib, sys
root=pathlib.Path(sys.argv[1]); name='sparky-stereo-language-tasks'
for path in (root/'usr/share/locale').glob('*/LC_MESSAGES/'+name+'.mo'):
    t=gettext.GNUTranslations(path.open('rb'))
    target=root/'usr/share/sparky'/name/path.parts[-3]
    target.parent.mkdir(parents=True,exist_ok=True)
    target.write_text('LOCAL1='+json.dumps(t.gettext('Shared language support'),ensure_ascii=False)+'\nLOCAL2='+json.dumps(t.gettext('Language support could not be completed: %s. Check the network and retry the update.'),ensure_ascii=False)+'\n')
PYCODE
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
Depends: python3, apt, dpkg, tasksel, systemd, sparky-stereo-problems
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: Shared language support
 Shared fonts, locales and input methods.
EOF
PYTHONPATH="$HERE/../.." python3 -m lean.standalone "$D" "$OUT" --authoring "$HERE"
