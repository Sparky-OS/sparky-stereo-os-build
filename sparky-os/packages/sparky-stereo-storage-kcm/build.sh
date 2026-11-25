#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Run in an isolated Debian build container with this recipe's build dependencies.
set -eu
: "${SOURCE_DATE_EPOCH:?}" "${OUT:?}"
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
toolkit=$(CDPATH= cd -- "$here/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT HUP INT TERM
export DEBEMAIL=Capitain_Jack@yahoo.com DEBFULLNAME='Daniel Ramos (Capitain Jack)'
cp -a -- "$here" "$work/source"
cd "$work/source"
PYTHONPATH="$toolkit" python3 -m lean.debian_prepare . 0.1.1+lc1 --toolkit "$toolkit"
python3 "$toolkit/repo/reproducible.py" normalize-tree "$SOURCE_DATE_EPOCH" .
case "${1:-}" in
    --source-only) dpkg-source -b . ;;
    '') dpkg-buildpackage -us -uc -j4 ;;
    *) exit 2 ;;
esac
mkdir -p -- "$OUT"
cp -- ../sparky-stereo-storage-kcm_* "$OUT/"
