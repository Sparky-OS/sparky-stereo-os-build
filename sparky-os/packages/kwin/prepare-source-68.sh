#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/26. Copyright 2026 under the GNU GPL3 License.
# Usage: prepare-source-68.sh STAGED_67_DIR OUT TOOLKIT; SOURCE_DATE_EPOCH is the recipe's date.
# STAGED_67_DIR holds the staged kwin_6.7.4-2+stereo3d67+lc1 source (row 71's stage: dsc, debian tarball, orig and its signature).
set -euo pipefail
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
HERE=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1")
out=$(realpath -m "$2")
toolkit=$(realpath "$3")
: "${SOURCE_DATE_EPOCH:?set the recipe date}"
printf '%s  %s\n' 5a46e9d6e4cb61fd4f7586edeb20e9bd2619bf43cd322de1c94ebd859f9c0e0b "$input/kwin_6.7.4-2+stereo3d67+lc1.dsc" | sha256sum -c
python3 "$toolkit/repo/lc-successor.py" --in-place --next 4:6.7.4-2+stereo3d68 --source-date-epoch "$SOURCE_DATE_EPOCH" \
 --overlay "$HERE/overlay-stereo3d68" \
 --item 'Known USB-C 3D glasses, by the published EDIDs of other owners: the XREAL Air 2 Pro (MRG 0x3135) and the VITURE Pro XR (CVT 0x3132) keep their 2D identity in Full SBS and announce one 3840x1080 at 60 Hz, so they come up in the side by side (full) twin as the XREAL One Pro does (queue row 132).' \
 --item 'The Nreal Light (MRG 0x3131), XREAL Air (MRG 0x3132), VITURE Beast (VIT 0x0120), Rokid Air (LBT 0x4752), Rokid Max (LBT 0x4753) and TCL SmartGlasses (TCL 0x03D4, 0x03D5), whose 2D EDID only is public, are known by identity: their output has its glasses option on, and the twin follows when they announce a mode two eyes wide.' \
 --item 'Tests: mockGlassesTest reads every one of those EDIDs (autotests/integration/data/*.hex, sources in usb-c-glasses-edids.txt) beside a 32:9 monitor and an ordinary monitor with the PnP ID MRG as controls, red on +67.' \
 "$input/kwin_6.7.4-2+stereo3d67+lc1.dsc" "$out"
