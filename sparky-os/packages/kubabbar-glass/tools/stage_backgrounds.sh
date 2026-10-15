#!/bin/bash
# Stage a reviewable payload; the main session integrates the look package.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
lane=$(dirname "$repo")
dest=/K3D/temp/sparky-os/pending-pack/classic-look/background-alpha
printf '%s\n' "$dest" >> "$lane/.artifacts"
mkdir -p "$dest/usr/share/plasma/desktoptheme" "$dest/integration"
for theme in kubabbar-glass sparky-stereo-oxygen; do
    cp -a "$repo/share/plasma/desktoptheme/$theme" "$dest/usr/share/plasma/desktoptheme/"
done
cp "$repo/LICENSE" "$dest/usr/share/plasma/desktoptheme/kubabbar-glass/COPYING"
cp "$repo/integration/README.md" "$repo/integration/oxygen-defaults.patch" "$dest/integration/"
cp "$repo/config/kwinrc" "$dest/integration/kwinrc-reference"
git -C "$repo" rev-parse HEAD > "$dest/SOURCE-COMMIT"
git -C "$repo" archive --format=tar.gz HEAD > "$dest/source.tar.gz"
(
    cd "$dest"
    rg --files --null -g '!SHA256SUMS' | LC_ALL=C sort -z | xargs -0 sha256sum > SHA256SUMS
)
printf 'Staged %s\n' "$dest"
