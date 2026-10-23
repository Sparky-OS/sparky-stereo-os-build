#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Proves the image and headers maintainer scripts of a kernel build against Debian's own (ORDER 222), in clean forky amd64 containers:
# fresh install, an upgrade over the previous build, a newer kernel next to it (/vmlinuz, /vmlinuz.old, /initrd.img, /initrd.img.old),
# removal of the older one, a package reinstalled over itself, removal of everything, and the refusal to remove the running kernel.
# The reference is Debian's linux-image-7.2.11+deb14-amd64 stack in the same steps; compare the printed states line by line.
#
#   kernel/tests/maint-scripts-proof.sh IMAGE DEBIAN_DEBS NEW_DEBS OLD_DEBS RELEASE_NEW RELEASE_OLD RELEASE_NEWER
# IMAGE: Debian forky amd64 image; DEBIAN_DEBS: Debian's linux-image/-binary/-modules/-base-7.2.11+deb14-amd64 debs;
# NEW_DEBS: the flavour's new linux-image and linux-headers; OLD_DEBS: the previous build's linux-image;
# RELEASE_*: kernel release names (RELEASE_NEWER is only a name: the new packages are repacked under it).
set -eu
HERE=$(cd "$(dirname "$0")/maint-proof" && pwd)
IMAGE=$1; DEB=$2; NEW=$3; OLD=$4; R1=$5; R0=$6; R2=$7
echo "##### Debian reference"
docker run --rm --platform linux/amd64 -v "$HERE":/proof:ro -v "$DEB":/debs:ro "$IMAGE" sh /proof/ref-debian.sh
echo "##### ours"
docker run --rm --platform linux/amd64 -v "$HERE":/proof:ro -v "$NEW":/new:ro -v "$OLD":/old:ro "$IMAGE" sh /proof/ours.sh "$R1" "$R0" "$R2"
echo "##### the running kernel is not removed without asking"
docker run --rm --platform linux/amd64 -v "$HERE":/proof:ro -v "$NEW":/new:ro "$IMAGE" sh /proof/ours-running.sh
