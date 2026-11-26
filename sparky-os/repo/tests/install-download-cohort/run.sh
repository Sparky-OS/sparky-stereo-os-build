#!/bin/bash
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
provider=$(realpath "${1:?the published ttf-mscorefonts-installer .deb}")
historic=$(realpath "${2:?the archived 20261114 shellprocess-corefonts.conf}")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/input" "$work/consumer/DEBIAN" "$work/consumer/etc/calamares/modules"
install -m644 "$historic" "$work/consumer/etc/calamares/modules/shellprocess-corefonts.conf"
cat > "$work/consumer/DEBIAN/control" <<'CONTROL'
Package: calamares-settings-sparky-stereo
Version: 20261114~sparky9~0
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Description: Installer cohort regression fixture
CONTROL
dpkg-deb --build "$work/consumer" "$work/input/calamares-settings-sparky-stereo_20261114~sparky9~0_all.deb"
# Run the exact package selection phase used before any pool or signature
# changes. Even a Debian fallback with the same package name is insufficient.
sed -n "/^import hashlib, os, re, sys, subprocess$/,/^PY$/p" "$repo/publish-tree.sh" |
    sed '$d' > "$work/select.py"
grep -q '^from install_download_cohort import ' "$work/select.py"
export PYTHONPATH="$repo:$repo/../packages/sparky-stereo-apt/install-downloads"
export PYTHONDONTWRITEBYTECODE=1
choose() {
    python3 "$work/select.py" "$work/input" "$work/selection.tsv" "$work/older.txt"
}
if choose > "$work/red.log" 2>&1; then
    echo 'FAIL 20261114 consumer without its provider was accepted' >&2
    exit 1
fi
grep -F 'requires ttf-mscorefonts-installer, which is absent from the selected round' "$work/red.log"
mkdir -p "$work/stock/DEBIAN"
cat > "$work/stock/DEBIAN/control" <<'CONTROL'
Package: ttf-mscorefonts-installer
Version: 3.8.1
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Description: Control for the stock provider
CONTROL
stock="$work/input/ttf-mscorefonts-installer_3.8.1_all.deb"
dpkg-deb --build "$work/stock" "$stock"
if choose > "$work/stock.log" 2>&1; then
    echo 'FAIL stock provider without the size and source was accepted' >&2
    exit 1
fi
grep -F 'ttf-mscorefonts-installer 3.8.1: the size and source declaration is missing' "$work/stock.log"
cp "$provider" "$work/input/"
choose
grep -F $'\tttf-mscorefonts-installer\t3.8.1+stereo3d2+lc1\tall' "$work/selection.tsv"
echo 'PASS historical consumer with the declared provider, including when the stock version is also present'

printf '\nSparky-Install-Download-Requires: ttf-mscorefonts-installer\n' |
    sed '/^$/d' >> "$work/consumer/DEBIAN/control"
sed -i '/^Version:/c\Version: 20261126.1+lc1' "$work/consumer/DEBIAN/control"
dpkg-deb --build "$work/consumer" "$work/input/calamares-settings-sparky-stereo_20261126.1+lc1_all.deb"
choose
grep -F $'\tcalamares-settings-sparky-stereo\t20261126.1+lc1\tall' "$work/selection.tsv"
echo 'PASS successor with the explicit consumer declaration'
