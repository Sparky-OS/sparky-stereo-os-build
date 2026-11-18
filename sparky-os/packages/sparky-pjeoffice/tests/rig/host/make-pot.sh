#!/bin/sh
# container-side: extract the template of the tray and the page
set -e
cd /pkg-rw
xgettext --from-code=UTF-8 -C -kde -ci18n -ki18n:1 -ki18nc:1c,2 -ki18np:1,2 -ki18ncp:1c,2,3 --package-name=sparky-pjeoffice -o /tmp/cpp.pot src/tray.cpp src/pjeofficekcm.cpp
xgettext --from-code=UTF-8 -L JavaScript -kde -ci18n -ki18n:1 -ki18nc:1c,2 -ki18np:1,2 -ki18ncp:1c,2,3 --package-name=sparky-pjeoffice -o /tmp/qml.pot src/ui/main.qml
msgcat --use-first /tmp/cpp.pot /tmp/qml.pot | grep -v '^#' | sed '/^"POT-Creation-Date/d' > po/sparky-pjeoffice.pot
grep -c '^msgid' po/sparky-pjeoffice.pot
