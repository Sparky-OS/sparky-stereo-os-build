#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# The page's and the helper's messages, one catalogue (kcm_sparkystereo_colourvision).
set -eu
${XGETTEXT:-xgettext} --from-code=UTF-8 --language=C++ --keyword=i18n --keyword=i18nc:1c,2 --sort-output \
    src/*.cpp src/ui/*.qml -o "${podir:-po}/kcm_sparkystereo_colourvision.pot"
${XGETTEXT:-xgettext} --from-code=UTF-8 --language=Python --keyword=tr --join-existing --sort-output \
    helper/sparky-stereo-colour-vision -o "${podir:-po}/kcm_sparkystereo_colourvision.pot"
