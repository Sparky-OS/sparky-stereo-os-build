#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/21
# Copyright 2026 under the GNU GPL3 License
# KDE's text add-ons follow the Partners page (ORDER 70): Debian's ktextaddons 2.1.2-8 with partners-follow.patch.
# Dictation with Vibe (ORDER 72): upstream's speech-to-text manager of v2.3.0, the vibe engine;
# upstream's settings dialog of v2.3.0 exported; every engine said when it cannot take a dictation, the Vibe server started
# at the press of the dictation button. The dictation catalogue patches follow their code.
# Run inside a clean distribution build container with the source dependencies installed.
# SOURCE_DSC names the unmodified Debian 2.1.2-8 source and its adjacent archives.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPRO="$HERE/../../repo/reproducible.py"
: "${SOURCE_DATE_EPOCH:?a source is dated by its recipe, never by the clock: export SOURCE_DATE_EPOCH (python3 sparky-os/repo/reproducible.py epoch RECIPE_DIR) or run through build-provenance.sh}"
SOURCE_DATE_RFC2822=$(python3 "$REPRO" rfc2822 "$SOURCE_DATE_EPOCH")
export SOURCE_DATE_EPOCH SOURCE_DATE_RFC2822
: "${SPARKY_LC_ARCHIVE_CONFIG:?Set an explicit public signed archive configuration}"
: "${SPARKY_LC_SCRATCH:?Set private archive qualification scratch}"
: "${LEAN_TOOLKIT:?Set the accepted archive-backed Lean Code toolkit}"
[ -f "$LEAN_TOOLKIT/lean/archive.py" ] || { echo 'Archive-backed Lean Code toolkit required' >&2; exit 1; }
: "${SOURCE_DSC:?Set SOURCE_DSC to Debian ktextaddons_2.1.2-8.dsc}"
: "${BUILD_ROOT:?Set BUILD_ROOT to a new disposable directory}"
: "${OUT:?Set OUT to a new candidate directory}"
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
export DEB_BUILD_OPTIONS="nocheck parallel=${JOBS:-4}" DEB_BUILD_PROFILES=nocheck
export LC_ALL=C.UTF-8
VERSION=2.1.2-8+stereo3d4
printf '%s  %s\n' a4c4bf0560d5dadd68e82bbf6b34a60fd5a6b9d1a0752919e8e1d0aa3c6de1ee "$SOURCE_DSC" | sha256sum -c -
[ ! -e "$BUILD_ROOT/authored" ] && [ ! -e "$OUT/authored" ]
mkdir -p "$BUILD_ROOT" "$OUT/authored"
cp "$(dirname "$SOURCE_DSC")"/ktextaddons_2.1.2.orig.tar.* "$BUILD_ROOT/"
dpkg-source -x "$SOURCE_DSC" "$BUILD_ROOT/authored"
cd "$BUILD_ROOT/authored"
mkdir -p debian/patches
for patch in partners-follow.patch speech-to-text-manager-v2.3.0.patch vibe-speech-to-text.patch vibe-speech-to-text-pt-br.patch \
	speech-to-text-dialog-export-v2.3.0.patch speech-engines-said-server-at-press.patch speech-engines-said-server-at-press-pt-br.patch \
	speech-to-text-eight-languages.patch; do
	cp "$HERE/$patch" debian/patches/
	printf '%s\n' "$patch" >> debian/patches/series
done
# the vibe engine is one more plugin of the speech-to-text library
printf '%s\n' 'usr/lib/*/qt6/plugins/kf6/speechtotext/speechtotext_vibe.so' >> debian/libkf6textspeechtotext1.install
# the vibe engine's files are ours: credited after Debian's paragraphs, each with its SPDX licence
cat >> debian/copyright <<'COPYRIGHT'

Files: textspeechtotext/speechtotext/plugins/vibe/*
Copyright: 2026 Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
License: GPL-2+
Comment: Sparky Stereo OS: the Vibe speech-to-text engine (ORDER 72).

Files: textspeechtotext/speechtotext/plugins/vibe/CMakeLists.txt
       textspeechtotext/speechtotext/plugins/vibe/autotests/CMakeLists.txt
Copyright: 2026 Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
License: BSD-3-Clause

Files: textspeechtotext/speechtotext/plugins/vibe/vibe.json
       textspeechtotext/speechtotext/plugins/vibe/vibe.json.license
       textspeechtotext/speechtotext/plugins/google/google.json
       textspeechtotext/speechtotext/plugins/google/google.json.license
       textspeechtotext/speechtotext/plugins/whisper/whisper.json
       textspeechtotext/speechtotext/plugins/whisper/whisper.json.license
Copyright: 2026 Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
License: CC0-1.0
COPYRIGHT
dpkg-source --before-build .
python3 - <<'PY'
from pathlib import Path
path = Path('debian/control')
text = path.read_text()
old = next(line for line in text.splitlines() if line.startswith('Maintainer: '))
text = text.replace(old, 'Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>\nXSBC-Original-' + old, 1)
home = next(line for line in text.splitlines() if line.startswith('Homepage: '))
text = text.replace(home, 'Homepage: https://sparkylinux.org\nBugs: https://github.com/Sparky-OS/sparky-stereo-os/issues', 1)
path.write_text(text)
PY
dch --date "$SOURCE_DATE_RFC2822" --newversion "$VERSION" --distribution mashtabba \
	'KDE text add-ons follow System Settings, Partners, when the person set up no instance; Start Ollama opens Partners; its two sentences in the ten languages (ORDER 70).'
dch --date "$SOURCE_DATE_RFC2822" --append \
	'Dictation with Vibe: upstream speech-to-text manager of 2.3.0 backported, a vibe engine that runs vibe-server only while a recording is transcribed, failures said to the person, Partners default for speech (ORDER 72).'
dch --date "$SOURCE_DATE_RFC2822" --append \
	'Every speech-to-text engine says why it cannot take a dictation (missing, its program missing, or not available in this version) and no other engine is taken in its place; upstream settings dialog of 2.3.0 exported; the Vibe server starts when dictation starts and stops at the answer, a cancel, the program closing or a failed recording (ORDER 72).'
python3 "$REPRO" normalize-tree "$SOURCE_DATE_EPOCH" .
dpkg-source -b .
cp "$BUILD_ROOT"/*.dsc "$BUILD_ROOT"/*.debian.tar.* "$BUILD_ROOT"/*.orig.tar.* "$OUT/authored/"
dpkg-source -x "$BUILD_ROOT/ktextaddons_${VERSION}.dsc" "$BUILD_ROOT/lean-source"
PYTHONPATH="$LEAN_TOOLKIT" python3 -m lean.debian_prepare "$BUILD_ROOT/lean-source" "$VERSION+lc1" --toolkit "$LEAN_TOOLKIT"
cd "$BUILD_ROOT/lean-source"
python3 "$REPRO" normalize-tree "$SOURCE_DATE_EPOCH" .
dpkg-buildpackage -us -uc -j"${JOBS:-4}"
# the stage is the source closure, in one folder: the archives, the .dsc and every file it names, the buildinfo and the changes
cp "$BUILD_ROOT"/*+lc1_*.deb "$BUILD_ROOT"/*+lc1.dsc "$BUILD_ROOT"/*+lc1.debian.tar.* "$BUILD_ROOT"/*.orig.tar.* \
	"$BUILD_ROOT"/*+lc1_*.buildinfo "$BUILD_ROOT"/*+lc1_*.changes "$OUT/"
# the release gate: every archive and its HR companions carry a valid lc1 record; the build record is written beside them
(cd "$OUT" && PYTHONPATH="$LEAN_TOOLKIT" python3 -m lean.release check-debs ./*.deb)
cp .sparky-lc/source.json "$OUT/native-source.json"
(cd "$OUT" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
