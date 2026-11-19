#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/10/16
# Copyright 2026 under the GNU GPL2 License
# Last update 2026/11/18
#
# Sparky Stereo OS: Debian's plymouth with the stereo boot splash patches (stereo3d-0001: a theme draws both eyes,
# stereo3d-0002: the DRM renderer's stereo outputs, stereo3d-0003: the person's depth limits for the theme,
# stereo3d-0004: one eye on every screen a stereo boot does not convert, the eyes at the main screen's size,
# stereo3d-0005: upstream's merge request !488, plymouth-set-default-theme stores a theme in a file that holds only its
# Daemon header, stereo3d-0006: the same command stores the choice or fails with a sentence, for an empty file too).
# tests/run.sh SCRIPT runs the real plymouth-set-default-theme on every shape of plymouthd.conf (ORDER 718).
# The authored source package is made once; the +lc1 source and the binaries come from it through
# sparky-os/release/build-dh-lean.sh (the tree is left in OUTDIR/plymouth-src beside the orig tarball; REAL_DIR=plymouth-26.134.222).
#   build.sh DEBIAN_DSC OUTDIR      (in a container with devscripts and quilt: dpkg-source, dch, quilt)
# DEBIAN_DSC is Debian's plymouth_26.134.222-1.dsc with its orig and debian tarballs beside it.
set -euo pipefail
HERE=$(dirname "$(readlink -f "$0")")
DSC=$(readlink -f "$1"); OUT=$(readlink -f "$2")
VERSION=26.134.222-1+stereo3d5
REPRO="$HERE/../../repo/reproducible.py"
: "${SOURCE_DATE_EPOCH:?a source is dated by its recipe, never by the clock: export SOURCE_DATE_EPOCH (python3 sparky-os/repo/reproducible.py epoch RECIPE_DIR) or run through build-provenance.sh}"
SOURCE_DATE_RFC2822=$(python3 "$REPRO" rfc2822 "$SOURCE_DATE_EPOCH")
export SOURCE_DATE_EPOCH SOURCE_DATE_RFC2822
export DEBFULLNAME="Daniel Ramos (Capitain Jack)" DEBEMAIL="Capitain_Jack@yahoo.com"
mkdir -p "$OUT"
cd "$OUT"
rm -rf plymouth-src
dpkg-source -x "$DSC" plymouth-src >/dev/null
cp "$(dirname "$DSC")"/plymouth_26.134.222.orig.tar.xz .
cd plymouth-src
export QUILT_PATCHES=debian/patches QUILT_REFRESH_ARGS="-p ab --no-timestamps --no-index"
for p in "$HERE"/stereo3d-*.patch; do
	cp "$p" debian/patches/
	echo "$(basename "$p")" >> debian/patches/series
	quilt push -q >/dev/null
done
# the new functions of libply-splash-core: 0001's three, 0003's two, 0004's five
python3 - debian/libplymouth5.symbols <<'PY'
import sys
path = sys.argv[1]
lines = open(path).read().split('\n')
new = {'ply_pixel_display_get_stereo_input': '26.134.222-1+stereo3d1~',
       'ply_pixel_display_set_stereo_input': '26.134.222-1+stereo3d1~',
       'ply_renderer_set_head_stereo_input': '26.134.222-1+stereo3d1~',
       'ply_pixel_display_get_stereo_depth_limits': '26.134.222-1+stereo3d3~',
       'ply_renderer_get_head_stereo_depth_limits': '26.134.222-1+stereo3d3~',
       'ply_pixel_display_set_shows_left_eye': '26.134.222-1+stereo3d4~',
       'ply_pixel_display_get_shows_left_eye': '26.134.222-1+stereo3d4~',
       'ply_pixel_display_get_stereo_main': '26.134.222-1+stereo3d4~',
       'ply_renderer_get_head_stereo_main': '26.134.222-1+stereo3d4~',
       'ply_pixel_buffer_fill_with_edges_of_area': '26.134.222-1+stereo3d4~'}
start = next(i for i, l in enumerate(lines) if l.startswith('libply-splash-core.so.5'))
end = next(i for i in range(start + 1, len(lines)) if lines[i] and not lines[i].startswith(' '))
block = lines[start + 1:end] + [' %s@Base %s' % (n, v) for n, v in new.items()]
block.sort(key=lambda l: l.strip().split('@')[0])
lines[start + 1:end] = block
open(path, 'w').write('\n'.join(lines))
PY
# the changelog: one entry for each version the edition has published, then this one
dch --date "$SOURCE_DATE_RFC2822" -v 26.134.222-1+stereo3d1 -D unstable --force-distribution "Stereo boot splash for Sparky Stereo OS (stereo3d-0001, stereo3d-0002):" >/dev/null
dch --date "$SOURCE_DATE_RFC2822" -a "plymouth.stereo= names the outputs that show two eyes and how: the HDMI 1.4b 3D structures (frame packing, side by side full and half, top and bottom) in the 3D mode the compositor keeps, and on 2D modes side by side and top and bottom by hand, anaglyph (Dubois, linear light), rows, columns, checkerboard, frame-sequential and the panels of a stereo pair (mirrored, iZ3D)." >/dev/null
dch --date "$SOURCE_DATE_RFC2822" -a "A theme declares Stereo=full-side-by-side to draw both eyes; the script plugin has Window.GetStereo (). Other themes show their picture in both eyes; nothing changes without plymouth.stereo=." >/dev/null
dch --date "$SOURCE_DATE_RFC2822" -a "debian/libplymouth5.symbols: the three new functions of libply-splash-core." >/dev/null
dch --date "$SOURCE_DATE_RFC2822" -v 26.134.222-1+stereo3d2 -D unstable --force-distribution "No-change rebuild of 26.134.222-1+stereo3d1 for the Lean Code toolkit 0.1.20 (ORDER 311, ORDER 334)." >/dev/null
dch --date "$SOURCE_DATE_RFC2822" -v 26.134.222-1+stereo3d3 -D unstable --force-distribution "The boot splash follows the person's depth limits (ORDER 481, stereo3d-0003):" >/dev/null
dch --date "$SOURCE_DATE_RFC2822" -a "plymouth.stereo= entries take popped=PIXELS and sunk=PIXELS, the main screen's depth limits as Stereo KWin resolves them (the person's PoppedLimit and SunkLimit built on the display), pixels of an eye 1920 wide; a malformed value is said and the default stands." >/dev/null
dch --date "$SOURCE_DATE_RFC2822" -a "The script plugin has Window.GetStereoPoppedLimit () and Window.GetStereoSunkLimit (), so a theme places its levels inside the limits. An entry without them gets the desktop's defaults, 4 and 10, and the renderer says once per output which of the two is missing." >/dev/null
dch --date "$SOURCE_DATE_RFC2822" -a "debian/libplymouth5.symbols: ply_pixel_display_get_stereo_depth_limits and ply_renderer_get_head_stereo_depth_limits." >/dev/null
dch --date "$SOURCE_DATE_RFC2822" -v 26.134.222-1+stereo3d4 -D unstable --force-distribution "One eye on every screen a stereo boot does not convert (ORDER 639, stereo3d-0004):" >/dev/null
dch --date "$SOURCE_DATE_RFC2822" -a "The script plugin keeps one window for every screen: on a stereo boot with a stereo theme it holds both eyes, each the size of the main screen's eye (the first screen plymouth.stereo= names). A screen that shows both eyes takes each half from its own eye of the window, a screen that shows one eye takes the middle of the left eye, and a screen larger than the eye continues the eye's own edge beyond it (each pixel the nearest pixel of the eye), so it shows no frame of another colour and never a part of the other eye; the eye is not scaled. Before, every screen was centred as one block in a window as wide as the widest screen, so a panel beside a television showed its anaglyph from two places 554 px apart and a television added later showed the left picture with the right one beside it." >/dev/null
dch --date "$SOURCE_DATE_RFC2822" -a "A screen that cannot take both eyes on a stereo boot (the frame-buffer renderer, the firmware's framebuffer before the GPU's driver, a rotated screen) shows the left eye and the window stays in both eyes for the others; before, its arrival or presence made the theme draw one picture for every screen. Said once per screen in Plymouth's log, as is a screen not named in plymouth.stereo= and a saved mode the screen does not list (it then keeps its own mode and shows the left eye; no other 3D mode is chosen in its place)." >/dev/null
dch --date "$SOURCE_DATE_RFC2822" -a "debian/libplymouth5.symbols: ply_pixel_display_set_shows_left_eye, ply_pixel_display_get_shows_left_eye, ply_pixel_display_get_stereo_main, ply_renderer_get_head_stereo_main and ply_pixel_buffer_fill_with_edges_of_area." >/dev/null
dch --date "$SOURCE_DATE_RFC2822" -v "$VERSION" -D unstable --force-distribution "A theme chosen with plymouth-set-default-theme is stored, or the command says why not (ORDER 718, stereo3d-0005 and stereo3d-0006):" >/dev/null
dch --date "$SOURCE_DATE_RFC2822" -a "stereo3d-0005 is upstream's merge request !488 (commit 3ada7716 by n3rdopolis, issue 348 by antohami): the command stored nothing, and exited 0, when /etc/plymouth/plymouthd.conf held only its [Daemon] header, which is the file a machine on the edition's default has; it also corrects sed -ie, which left plymouthd.confe beside the file." >/dev/null
dch --date "$SOURCE_DATE_RFC2822" -a "stereo3d-0006 handles what !488 leaves: an empty file and a Daemon header with no newline after it (the line count was 1 for an empty file), written the way !488 does it (add the missing empty line, then insert). The Theme is read back and a mismatch fails with a sentence and a non-zero exit; a file or folder that cannot be written fails before anything changes (the legacy default.plymouth link stays), naming it; --reset deletes the Theme line of the Daemon section only." >/dev/null
quilt pop -a -q >/dev/null
rm -rf .pc
python3 "$REPRO" normalize-tree "$SOURCE_DATE_EPOCH" .
cd "$OUT"
ls
