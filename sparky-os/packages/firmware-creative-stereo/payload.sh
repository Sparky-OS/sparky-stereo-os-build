#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/03
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/03
set -euo pipefail
mkdir -p "$D/usr/lib/firmware/updates"
(cd "$HERE/firmware" && sha256sum -c SHA256SUMS)
install -m644 "$HERE"/firmware/*.bin "$D/usr/lib/firmware/updates/"
install -m644 "$HERE/firmware/creative.txt" "$D/usr/share/doc/firmware-creative-stereo/creative.txt"
