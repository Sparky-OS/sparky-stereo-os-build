#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Run from this recipe with the layer development package installed.
set -eu
messages=$(mktemp -d)
trap 'rm -rf "$messages"' EXIT HUP INT TERM
${CC:-cc} tools/packing-messages.c $(pkg-config --cflags --libs stereo-policy) -o "$messages/packing-messages"
"$messages/packing-messages" >"$messages/packings.cpp"
${XGETTEXT:-xgettext} --from-code=UTF-8 --language=C++ --keyword=i18n --keyword=i18nc:1c,2 \
    --keyword=i18np:1,2 --keyword=i18ncp:1c,2,3 --sort-output \
    src/*.cpp src/*.h src/ui/*.qml "$messages/packings.cpp" \
    -o "${podir:-po}/kcm_sparkystereo_camera.pot"
