#!/bin/sh
# Created by Daniel Ramos (Capitain Jack) 2026/11/21
# Copyright 2026 under the GNU GPL3 License
# The template of the page's one catalogue, kcm_sparkystereo_partners: the page (QML and C++, KDE's i18nc) and its command
# (tr(CONTEXT, TEXT) in Python, the same catalogue through gettext's pgettext). Then each language is merged with msgmerge.
set -eu
cd "$(dirname "$0")/.."
xgettext --from-code=UTF-8 -C --kde -ci18n -ki18n:1 -ki18nc:1c,2 -ki18np:1,2 -ki18ncp:1c,2,3 --no-wrap --sort-by-file \
	--package-name=sparky-stereo-partners -o po/qml.pot src/*.cpp src/ui/*.qml
xgettext --from-code=UTF-8 -L Python -ktr:1c,2 -kkey:1c,2 -kkeep:2c,3 --no-wrap --sort-by-file --package-name=sparky-stereo-partners -o po/py.pot bin/sparky-stereo-partners
msgcat --no-wrap --use-first po/qml.pot po/py.pot -o po/kcm_sparkystereo_partners.pot
rm -f po/qml.pot po/py.pot
for po in po/*/kcm_sparkystereo_partners.po; do
	[ -f "$po" ] && msgmerge -q --no-wrap --no-fuzzy-matching -U --backup=none "$po" po/kcm_sparkystereo_partners.pot
done
