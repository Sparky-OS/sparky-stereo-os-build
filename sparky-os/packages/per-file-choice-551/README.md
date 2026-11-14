# The per-file 3D choice as packages (ORDER 551, continuing ORDER 512)

stereo-layer 1.18.0-1+lc1, kf6-kimageformats 6.30.0-1+stereo3d7+lc1, dolphin 4:26.08.0-1+stereo3d7+lc1, ffmpegthumbs 4:26.04.0-1+stereo3d5+lc1 and gwenview 4:26.04.0-1+stereo3d10+lc1, with kio-extras 4:26.04.0-1+stereo3d5+lc1 as ORDER 504 staged it.

A person's choice for one file (the input packing chosen by hand, Not 3D, the swap of the eyes) is kept once, in the stereo layer's store, and every program on the layer shows the file by it: Dolphin, its thumbnailers, the information panel and Gwenview.
The file is never written unless the person chooses "Save the correction into the file".

Design followed (Daniel's words, as recorded):
- Never touch the user's file (2026-10-23): "never touch the user file, it's the same place where the continue playback is saved (as another indicator per file)"; "change it to offer the user to save to the file"; "when accepted, it's apply to the file and leave the option unmarked".
- Corrections for media, declared or not (2026-10-31): a program that shows media files offers the input packing and the swap for every file shown in 3D, because a declaration can be wrong.
- The shared layer (2026-10-07): "Each viewer keeps only its view adapter and its 3D menu"; the menu itself is the layer's since ORDER 512.
- Engine, not per program (2026-10-07): "as little code to devs as possible, intervene in the engine instead of per case".
- Nothing fails silently (2026-11-01): "either it works or not and the user must know".

## Files

- `patches/dolphin-per-file-stereo-choice.patch`: the layer's menu in the context menu for pictures and videos, the swap in the store, the follower of renamed and moved files.
- `patches/ffmpegthumbs-per-file-stereo-choice.patch`: the video thumbnailer reads the store; a hand-chosen anaglyph gives both views.
- `patches/gwenview-shared-per-file-choice.patch`: Gwenview's per-file 3D entries are the layer's menu and store, with the one-time carry of the swaps it kept in gwenviewstereorc; applied after `../viewers-504/patches/stereo-opaque-picture-background.patch` (+stereo3d9 was staged and never published).
- `changelog/*.items`: the changelog items, one paragraph per item.
- `next-source.sh PACKAGE PUBLISHED.dsc OUT`: the next +lc1 source of dolphin, ffmpegthumbs or gwenview (`repo/lc-successor.py --in-place --overlay`): the published history stays a byte identical suffix of the new changelog, and nothing else of debian/ changes but the patches, the series, the layer's version in Build-Depends and the configure line of the rules.
- `kimageformats-source.sh`: the +lc1 source of kf6-kimageformats +stereo3d7 from `../jps-descriptor` (ORDER 526), which no round had built.
- `round.sh WORK STEREO_LAYER_CLONE REV PUBLISHED_TREE ARCHIVE_DIR KIO_EXTRAS_DIR [STEP...]`: every build in order (the bootstrap of the policy library first), each through `../depth-source/build.sh` (Lean Code, the link and start gate, `lean.release check-debs`), collected in a flat repository with the edition's Origin for the next one.

## Order, and why

`libstereo-layer1` depends on `kimageformat6-plugins (>= 6.30.0-1+stereo3d6)`: the shared save reads a JPS descriptor back through that plugin.
The plugin +stereo3d7 is built against the layer's policy library (`libstereo-policy-dev (>= 1.17.5)`).
Published are stereo-layer 1.17.1 and the plugin +stereo3d5, so neither new package passes the link gate before the other exists: the gate installs each candidate from the edition's archive, and says "libstereo-layer1 ... is not going to be installed" for a layer without its plugin.
The policy library depends on neither, and that is where the round starts.

0. A bootstrap of `libstereo-policy1` and `libstereo-policy-dev`: a plain `dpkg-buildpackage -b -Pnocheck` of the layer's source, in the round's repository for step 1 only, never published.
1. kf6-kimageformats +stereo3d7 through the gate, against the bootstrap policy library.
2. stereo-layer 1.18.0-1+lc1 through the gate, with the plugin of step 1 present and the bootstrap debs removed, under `SPARKY_BUILD_PROFILES=nocheck`.
   The package build runs no tests in either case (`DEB_BUILD_OPTIONS=nocheck`); the layer's tests run in the review's own harness with the plugin of step 1.
3. kio-extras +stereo3d5 as staged by ORDER 504 (its thumbnail worker calls `Stereo::Picture::loadPair(path, size, {})`, so the layer applies the store and the package needs no change).
4. dolphin, ffmpegthumbs and gwenview.

## The build stops on an older layer

Each of the three programs finds the layer with an optional `find_package(StereoLayer 1.18 CONFIG)`, so that the same source builds on KDE's CI, which has no layer.
With an older `libstereo-layer-dev` installed that call finds nothing, CMake prints no error and the program is built without stereo.
The edition's packages therefore name the version in `Build-Depends` and pass `-DCMAKE_REQUIRE_FIND_PACKAGE_StereoLayer=ON` (CMake's own switch, which Gwenview's rules already used): configure then stops with "Could not find a configuration file for package "StereoLayer" that is compatible with requested version "1.18"" and lists the version it found.

## Dependencies added or changed

- dolphin, ffmpegthumbs, gwenview: `libstereo-layer-dev (>= 1.18.0)` in Build-Depends (from 1.4.0, 1.5.0 and 1.11.0-1+lc1); the edition's own package, built in step 1.
- stereo-layer: `dbus-daemon <!nocheck>` in Build-Depends (the test of the follower of renamed and moved files runs under `dbus-run-session`); Debian's package, checked with `apt-cache policy` in the build container.
- No runtime dependency is new: `libstereo-layer1` links `libqt6dbus6`, which `dh_shlibdeps` names.
