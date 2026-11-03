#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/03
# Copyright 2026 under the GNU GPL3 License
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?Set OUT}
SOURCE=${APTUS_SOURCE:-$HERE/../../sparky-aptus-stereo-appcenter}
VERSION=0.1.1+lc1
PACKAGE=sparky-aptus-stereo-appcenter
mkdir -p "$OUT"
WORK=$(mktemp -d "$OUT/.aptus-stereo.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
D=$WORK/$PACKAGE
mkdir -p "$D/DEBIAN" "$D/usr/lib/$PACKAGE" "$D/usr/share/sparky/$PACKAGE" "$D/usr/share/doc/$PACKAGE" "$D/usr/bin" "$D/usr/share/applications" "$D/usr/share/polkit-1/actions"
python3 "$HERE/../../../tools/copy-recipe.py" "$SOURCE/stereo" "$WORK/source"
install -m755 "$WORK/source/appcenter" "$D/usr/lib/$PACKAGE/appcenter"
install -m755 "$WORK/source/handler" "$D/usr/lib/$PACKAGE/handler"
install -m644 "$WORK/source/ATTRIBUTIONS.md" "$D/usr/lib/$PACKAGE/ATTRIBUTIONS.md"
install -m644 "$WORK/source/common.py" "$D/usr/lib/$PACKAGE/common.py"
install -Dm755 "$WORK/source/actions/zram" "$D/usr/lib/$PACKAGE/actions/zram"
install -m644 "$WORK/source/lang/"*.json "$D/usr/share/sparky/$PACKAGE/"
printf '#!/bin/sh\nexec /usr/lib/sparky-aptus-stereo-appcenter/appcenter "$@"\n' > "$D/usr/bin/$PACKAGE"
chmod 755 "$D/usr/bin/$PACKAGE"
install -m644 "$HERE/copyright" "$D/usr/share/doc/$PACKAGE/copyright"
install -m644 "$HERE/README.md" "$HERE/CHANGELOG" "$WORK/source/ATTRIBUTIONS.md" "$D/usr/share/doc/$PACKAGE/"
sparky-stereo-problems catalog "$PACKAGE" "$WORK/source/lang" "$D/usr/lib/systemd/catalog" --subject LOCAL1
python3 - "$WORK/source/lang" "$D" <<'PY'
from pathlib import Path
import json, sys
from xml.sax.saxutils import escape
lang, root = map(Path,sys.argv[1:])
texts={p.stem:json.loads(p.read_text()) for p in lang.glob('*.json')}
desktop='[Desktop Entry]\nVersion=1.0\nType=Application\nName=Stereo APTus\nExec=pkexec /usr/bin/sparky-aptus-stereo-appcenter\nIcon=system-software-install\nTerminal=false\nCategories=System;PackageManager;\n'
for code,d in sorted(texts.items()): desktop+=f'Comment[{code}]={d["categories"]}\n'
(root/'usr/share/applications/sparky-aptus-stereo-appcenter.desktop').write_text(desktop)
policy='<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE policyconfig PUBLIC "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN" "http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd">\n<policyconfig>\n'
for key,path,gui in [('launch','/usr/bin/sparky-aptus-stereo-appcenter',True),('zram','/usr/lib/sparky-aptus-stereo-appcenter/actions/zram',False)]:
    policy+=f'<action id="org.sparkylinux.sparkystereo.aptus.{key}"><description>Stereo APTus</description><message>{escape(texts["en"]["authorization"])}</message>'
    for code,d in sorted(texts.items()): policy+=f'<message xml:lang="{code}">{escape(d["authorization"])}</message>'
    policy+='<defaults><allow_any>no</allow_any><allow_inactive>auth_admin</allow_inactive><allow_active>auth_admin</allow_active></defaults>'
    policy+=f'<annotate key="org.freedesktop.policykit.exec.path">{path}</annotate>'
    if gui: policy+='<annotate key="org.freedesktop.policykit.exec.allow_gui">true</annotate>'
    policy+='</action>\n'
policy+='</policyconfig>\n'
(root/'usr/share/polkit-1/actions/org.sparkylinux.sparkystereo.aptus.policy').write_text(policy)
PY
cat > "$D/DEBIAN/control" <<EOF
Package: $PACKAGE
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Depends: sparky-aptus-appcenter, python3, apt, dpkg, systemd, udev, kmod, pkexec, yad, sparky-stereo-problems (>= 0.1.1)
Section: admin
Priority: optional
Homepage: https://sparkylinux.org
Description: Stereo APTus choices beside SparkyLinux AppCenter
 Offers the person's compressed RAM swap opt-in and links to the original
 AppCenter categories. The original package and its files stay untouched.
EOF
cat > "$D/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = remove ] && command -v sparky-stereo-problems >/dev/null 2>&1; then
    sparky-stereo-problems clear --all sparky-aptus-stereo-appcenter
fi
EOF
chmod 755 "$D/DEBIAN/postrm"
(cd "$D" && find usr -type f -print0 | sort -z | xargs -0 md5sum > DEBIAN/md5sums)
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone "$D" "$OUT" --authoring "$HERE" --build-dependency sparky-stereo-problems
