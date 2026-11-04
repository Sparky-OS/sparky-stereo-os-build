#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/04
# Copyright 2026 under the GNU GPL3 License
# ORDER 346f-3b: a fixture for stereo-display-info without a graphics card: a fake /sys/class/drm with two connected displays (an
# HDMI television that announces 3D and HDR, a DisplayPort monitor behind nothing) and fake edid-decode, kscreen-doctor, wayland-info,
# uname, dpkg-query, eglinfo and vulkaninfo that print fixed text. Usage: fixture.sh DIR  (then run the script with SPARKY_STEREO_INFO_DRM=DIR/drm and
# PATH=DIR/bin:...). The text is shaped like the real tools' output, as far as the script reads it.
set -eu
D=${1:?the fixture folder}
rm -rf "$D"; mkdir -p "$D"; D=$(cd "$D" && pwd)
mkdir -p "$D/bin" "$D/drm/card0/device" "$D/drm/card0-HDMI-A-1" "$D/drm/card0-DP-1" "$D/drivers/amdgpu"
ln -s "$D/drivers/amdgpu" "$D/drm/card0/device/driver"
echo 0x1002 >"$D/drm/card0/device/vendor"
echo 0x73bf >"$D/drm/card0/device/device"
printf 'EDID-TV' >"$D/drm/card0-HDMI-A-1/edid"
printf 'EDID-MON' >"$D/drm/card0-DP-1/edid"
echo connected >"$D/drm/card0-HDMI-A-1/status"
echo connected >"$D/drm/card0-DP-1/status"
printf '1920x1080\n1280x720\n' >"$D/drm/card0-HDMI-A-1/modes"
printf '2560x1440\n' >"$D/drm/card0-DP-1/modes"
cat >"$D/bin/edid-decode" <<'EOF'
#!/bin/sh
case "$(cat "$1")" in
EDID-TV) cat <<'TV'
Block 0, Base EDID:
  EDID Structure Version & Revision: 1.3
  Vendor & Product Identification:
    Manufacturer: SNY
    Model: 1234
    Made in: week 10 of 2011
  Basic Display Parameters & Features:
    Maximum image size: 98 cm x 55 cm
  Detailed Timing Descriptors:
    DTD 1:  1920x1080   60.000000 Hz  16:9    67.500 kHz  148.500 MHz (1018 mm x 573 mm)
    Display Product Name: 'SONY TV'
Block 1, CTA-861 Extension Block:
  Vendor-Specific Data Block (HDMI), OUI 00-0C-03:
    Source physical address: 1.0.0.0
    DC_36bit
    DC_30bit
    DC_Y444
    Maximum TMDS clock: 225 MHz
    3D present
    3D: Frame packing
    3D: Side-by-side (half, horizontal)
    3D VIC indices that support these capabilities:
      VIC  16:  1920x1080   60.000000 Hz  16:9
      VIC  31:  1920x1080i  50.000000 Hz  16:9
    3D VIC indices with specific capabilities:
      VIC  32:  1920x1080   24.000000 Hz  16:9 (Top-and-bottom)
  HDR Static Metadata Data Block:
    Electro optical transfer functions:
      Traditional gamma - SDR luminance range
      SMPTE ST2084
      Hybrid Log-Gamma
  Colorimetry Data Block:
    BT2020RGB
TV
;;
*) cat <<'MON'
Block 0, Base EDID:
  Vendor & Product Identification:
    Manufacturer: DEL
    Model: 41234
  Basic Display Parameters & Features:
    Bits per primary color channel: 8
    Maximum image size: 60 cm x 34 cm
  Detailed Timing Descriptors:
    DTD 1:  2560x1440  144.000000 Hz  16:9   222.000 kHz  592.000 MHz (597 mm x 336 mm)
    Display Product Name: 'DELL S2721DGF'
MON
;;
esac
EOF
cat >"$D/bin/kscreen-doctor" <<'EOF'
#!/bin/sh
if [ "$1" = -j ]; then
cat <<'JSON'
{
    "outputs": [
        {
            "anaglyph": false,
            "hdr": true,
            "name": "HDMI-A-1",
            "otherStereoFormats": true,
            "stereoEyeSwap": false,
            "wcg": true
        },
        {
            "hdr": false,
            "name": "DP-1",
            "wcg": false
        }
    ]
}
JSON
else
printf 'Output: 1 HDMI-A-1 enabled connected\n\tModes: 0:3840x1080@60.00*(3D-SBS-full) 1:1920x1080@60.00\n\tColor profile source: EDID\n\tColor resolution: automatic (10 bits per color), range: [8; 12]\n'
printf 'Output: 2 DP-1 enabled connected\n\tModes: 0:2560x1440@143.91*!\n\tColor profile source: ICC\n\tICC profile: /home/p/.local/share/icc/calibrated.icc\n\tColor resolution: 8 bits per color, range: [8; 10]\n'
printf 'Output: 3 Virtual-1 enabled connected\n\tModes: 0:1280x720@60.00*\n\tColor resolution: unknown, range: [8; 8]\n'
fi
EOF
cat >"$D/bin/wayland-info" <<'EOF'
#!/bin/sh
echo "interface: 'kde_stereo_content_manager_v1', version: 2, name: 31"
EOF
cat >"$D/bin/eglinfo" <<'EOF'
#!/bin/sh
printf 'Device platform:\nOpenGL core profile vendor: AMD\nOpenGL core profile renderer: AMD Radeon RX 6800\nOpenGL core profile version: 4.6 Mesa 26.1\n'
EOF
cat >"$D/bin/vulkaninfo" <<'EOF'
#!/bin/sh
printf 'GPU0:\n\tvendorID = 0x1002\n\tdeviceID = 0x73bf\n\tdeviceName = AMD Radeon RX 6800\n\tdriverName = radv\n\tdriverInfo = Mesa 26.1\n'
EOF
printf 'DEL\tDell Inc.\nSNY\tSony\n' >"$D/pnp.ids"
cat >"$D/bin/uname" <<'EOF'
#!/bin/sh
echo 7.0.0-test
EOF
cat >"$D/bin/dpkg-query" <<'EOF'
#!/bin/sh
printf 'ii  kscreen 4:6.7.4-1\nii  kwin-wayland 4:6.7.4-2\n'
EOF
chmod +x "$D"/bin/*
