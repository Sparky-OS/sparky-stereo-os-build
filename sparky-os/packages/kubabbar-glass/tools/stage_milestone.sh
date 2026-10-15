#!/bin/bash
# Stage the first drawings for review, without installing into a session.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
lane=$(dirname "$repo")
dest=/K3D/temp/sparky-os/pending-pack/classic-look/kubabbar-glass
printf '%s\n' "$dest" >> "$lane/.artifacts"
mkdir -p "$dest/usr/share" "$dest/integration"
cp -a "$repo/share/." "$dest/usr/share/"
cp "$repo/README.md" "$repo/ABOUT.md" "$repo/LICENSE" "$repo/copyright" "$dest/"
cp "$repo/config/kwinrc" "$dest/integration/kwinrc-reference"
cp "$repo/integration/README.md" "$repo/integration/oxygen-defaults.patch" "$dest/integration/"
git -C "$repo" rev-parse HEAD > "$dest/SOURCE-COMMIT"
(
    cd "$dest"
    rg --files --null -g '!SHA256SUMS' | LC_ALL=C sort -z | xargs -0 sha256sum > SHA256SUMS
)
printf 'Staged first drawings: %s\n' "$dest"
