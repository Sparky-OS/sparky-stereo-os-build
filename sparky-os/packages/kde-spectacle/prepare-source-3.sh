#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/20. Copyright 2026 under the GNU GPL3 License.
# Usage: prepare-source-3.sh PUBLISHED_2_DIR OUT TOOLKIT
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
: "${SOURCE_DATE_EPOCH:?set the recipe date}"
printf '%s  %s\n' 11936715a0f1c2e613658952bea278925252fcba3ecb537981cc11b503b12df1 "$1/kde-spectacle_6.7.4-1+stereo3d2+lc1.dsc" | sha256sum -c
python3 "$HERE/prepare-source.py" "$1" "$2" "$3"
