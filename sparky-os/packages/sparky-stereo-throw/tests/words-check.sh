#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-2.0-or-later
# The words: the package's table passes, and the check fails on a known bad copy (a lost %1, "Throw" translated
# away, a missing language): three faults, no more, no less. Exit 0 when both hold.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
TOOLS=$HERE/../po/tools
python3 -I "$TOOLS/check-po.py" || { echo "FAIL: the package's own table"; exit 1; }
BAD=$(mktemp --suffix=.py)
trap 'rm -f "$BAD"' EXIT
python3 -I - "$TOOLS/strings.py" "$BAD" <<'PY'
import sys
s = open(sys.argv[1]).read()
s = s.replace('"pt_BR": "O Throw para %1 não conseguiu iniciar a transmissão: %2"', '"pt_BR": "O Throw não conseguiu iniciar a transmissão: %2"', 1)
s = s.replace('"pt_BR": "%1 encerrou o Throw."', '"pt_BR": "%1 encerrou o jogar."', 1)
s = s.replace('"de": "Der Throw-Dienst läuft nicht (org.sparky.Throw).",', '', 1)
open(sys.argv[2], "w").write(s)
PY
python3 -I "$TOOLS/check-po.py" "$BAD" > "$BAD.out"
faults=$?
cat "$BAD.out"
rm -f "$BAD.out"
[ "$faults" = 3 ] && echo "RESULT: the check fails the bad copy with 3 faults" || { echo "FAIL: the bad copy gave $faults faults, 3 expected"; exit 1; }
# every sentence the code shows is in the table: the recipe passes, a copy whose page shows one more sentence fails
python3 -I "$TOOLS/check-sources.py" "$HERE/.." || { echo "FAIL: a sentence of the sources is not in the table"; exit 1; }
COPY=$(mktemp -d)
trap 'rm -rf "$BAD" "$COPY"' EXIT
cp -r "$HERE/../kcm" "$HERE/../src" "$COPY/"
mkdir -p "$COPY/po" && ln -s "$TOOLS" "$COPY/po/tools"
sed -i 's|text: i18ndc("sparky-stereo-throw", "@info no Cast device announced itself"|text: i18ndc("sparky-stereo-throw", "@info", "A sentence nobody translated.") + i18ndc("sparky-stereo-throw", "@info no Cast device announced itself"|' "$COPY/kcm/ui/main.qml"
python3 -I "$TOOLS/check-sources.py" "$COPY"
missing=$?
[ "$missing" = 1 ] && echo "RESULT: the sources check fails the copy with 1 missing sentence" || { echo "FAIL: the copy gave $missing, 1 expected"; exit 1; }
