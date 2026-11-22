#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/22
# Copyright 2026 under the GNU GPL3 License
# KDE's speech-to-text library with the Vibe engine (ORDER 72): build the library, its engines, the Vibe engine's tests and
# upstream's test program from a patched source tree, then run every speech-to-text test against the stand-in vibe-server:
# the engine's job, the loader, the engine through the plugin interface (when its server runs), the manager (what is said
# when the engine chosen cannot take a dictation) and the settings (said as soon as it is chosen).
# No model and no network: the stand-in answers with a fixed text. Run it in a build container as an ordinary user.
# Use: speech-to-text.sh PATCHED_SOURCE NEW_BUILD_FOLDER
set -euo pipefail
SRC=${1:?the patched source tree (dpkg-source -x of the package, or a work tree)}
BUILD=${2:?a new build folder}
[ ! -e "$BUILD" ] || { echo "speech-to-text.sh: $BUILD exists; give a new folder" >&2; exit 2; }
command -v python3 >/dev/null || { echo "speech-to-text.sh: python3 is needed for the stand-in vibe-server" >&2; exit 2; }
export QT_QPA_PLATFORM=offscreen LC_ALL=C.UTF-8
cmake -S "$SRC" -B "$BUILD" -DBUILD_TESTING=ON -DBUILD_QCH=OFF -DBUILD_DESIGNERPLUGIN=OFF -DCMAKE_BUILD_TYPE=Debug >"$BUILD.configure.log" 2>&1 \
	|| { tail -20 "$BUILD.configure.log" >&2; exit 1; }
cmake --build "$BUILD" -j"${JOBS:-4}" --target speechtotext_vibe speechtotext_whisper speechtotext_google \
	vibespeechtotextjobtest vibespeechtotextloadertest0 vibespeechtotextloadertest1 vibespeechtotextplugintest \
	speechtotextmanagertest0 speechtotextmanagertest1 speechtotextenginemessagetest speechtotextgui >"$BUILD.build.log" 2>&1 \
	|| { grep -E 'error|Error' "$BUILD.build.log" | head -40 >&2; exit 1; }
ctest --test-dir "$BUILD" -R 'textspeechtotext-vibe-' --output-on-failure -V
