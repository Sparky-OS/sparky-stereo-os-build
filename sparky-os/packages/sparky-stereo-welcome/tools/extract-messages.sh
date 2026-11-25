#!/bin/sh
# Created by Daniel Ramos (Capitain Jack) 2026/11/25
# Copyright 2026 under the GNU GPL3 License
# po/sparky-stereo-welcome.pot from the pages, as KDE's own Messages.sh scripts read QML (as C++, with KDE's keywords;
# the domain is the first argument of i18ndc and xi18ndc and is left out), then each po/LANG.po merged with it.
# Needs gettext (xgettext, msgmerge).
set -eu
HERE=$(cd "$(dirname "$0")/.." && pwd)
cd "$HERE"
xgettext --from-code=UTF-8 -C --kde --no-location --package-name=sparky-stereo-welcome \
	--msgid-bugs-address=https://github.com/Sparky-OS/sparky-stereo-os/issues \
	-ki18ndc:2c,3 -kxi18ndc:2c,3 -o po/sparky-stereo-welcome.pot first-pages/*.qml extra-pages/*.qml
for po in po/*.po; do
	[ -e "$po" ] || continue
	msgmerge --quiet --update --backup=none --no-fuzzy-matching "$po" po/sparky-stereo-welcome.pot
done
