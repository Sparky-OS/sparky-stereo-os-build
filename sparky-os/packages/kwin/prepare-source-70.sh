#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/26. Copyright 2026 under the GNU GPL3 License.
# Usage: prepare-source-70.sh STAGED_69_DIR OUT TOOLKIT
set -euo pipefail
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
here=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1")
out=$(realpath -m "$2")
toolkit=$(realpath "$3")
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$toolkit/repo/reproducible.py" epoch "$here")}
export SOURCE_DATE_EPOCH
mkdir -p "$(dirname "$out")"
overlay=$(mktemp -d "$(dirname "$out")/kwin-70-overlay-XXXXXX")
trap 'rm -rf "$overlay"' EXIT
cp -a "$here/overlay-stereo3d70/." "$overlay/"
# Keep the canonical translations in the edition's catalogue tree. Compose the
# source closure's existing patch from its code and catalogues.
python3 - "$overlay" "$toolkit/translations/kwin-element-limit.po.patch" <<'COMPOSE'
from pathlib import Path
import sys

overlay = Path(sys.argv[1])
patch = overlay / "patches/s70-0002-Expose-ElementLimit-in-the-3D-Depth-page.patch"
translation = Path(sys.argv[2]).read_text()
head, code = patch.read_text().split("diff --git ", 1)
patch.write_text(head + translation + "diff --git " + code)
COMPOSE
python3 "$toolkit/repo/lc-successor.py" --in-place --next 4:6.7.4-2+stereo3d70 --source-date-epoch "$SOURCE_DATE_EPOCH" \
    --overlay "$overlay" \
    --item 'Send both element steps using the selected output depth factors, including directional display overrides (row 121).' \
    --item 'Add Element limit to the 3D Depth page and translate its label and help.' \
    "$input/kwin_6.7.4-2+stereo3d69+lc1.dsc" "$out"
for name in kwin_6.7.4.orig.tar.xz kwin_6.7.4.orig.tar.xz.asc; do
    if [ ! -e "$out/$name" ]; then
        cp "$input/$name" "$out/"
    fi
done
