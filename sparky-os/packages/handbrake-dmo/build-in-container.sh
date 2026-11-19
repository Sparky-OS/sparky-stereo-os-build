#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
ulimit -c 0
sh /run/https-only-apt.sh
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
cohort=()
for family in x264 x265 ffmpeg; do
    for archive in /work/"$family"-build/*.deb; do
        case "$archive" in *-dbgsym_*) continue ;; esac
        cohort+=("$archive")
    done
done
apt-get -y --no-install-recommends install "${cohort[@]}"
python3 /recipe/pin-local-built.py "${cohort[@]}"
python3 /recipe/check-required-encoders.py
source_trees=(/work/handbrake-shared/handbrake-dmo-*)
[ "${#source_trees[@]}" = 1 ]
apt-get -y --no-install-recommends build-dep "${source_trees[0]}"
id builder >/dev/null 2>&1 || useradd --uid 1000 --no-create-home builder
chown -R builder:builder /work/handbrake-shared
cd "${source_trees[0]}"
runuser -u builder -- dpkg-buildpackage -us -uc -sa -j4
cd ..
PYTHONPATH="${source_trees[0]}/debian/sparky-lean-toolkit" python3 -m lean.release check-debs ./*.deb
