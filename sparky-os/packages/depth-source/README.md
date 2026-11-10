# Depth as a 3D source in Qt Multimedia and Dragon (ORDER 151, step R part 2, group 2)

qt6-multimedia 6.11.2-3+stereo3d14+lc1 and dragon 4:26.04.0-1+stereo3d7+lc1 (stereo3d6 was staged and never published; stereo3d7 carries its work and the offer to save the 3D correction into the file, ORDER 411).
A picture with its depth map (2D plus depth) is decoded like any other packing and handed to Stereo KWin as full side by side, each eye at the size the video holds.

Design followed (Daniel's words, as recorded):
- Engine, not per program (2026-10-07): "intervene in the engine instead of per case ... qt multimedia it is."
- Depth is a stereo format (2026-10-16): "it's fundamental, don't you think? LG will like to see it there".
- A program's 3D options are only enable 3D, render resolution per eye and a shortcut to Display Settings; a player adds the input packing and a per-file swap of left and right eyes (2026-10-31).
- Never touch the user's file (2026-10-23): the packing and the swap are kept in the program's per-file store, and the program offers to save them into the file; it writes only when the person says yes, then unmarks the stored choice (ORDER 411: `patches/dragon/0005`, the writers in stereo-layer 1.13.0's `stereo_mark_save`).

## Files

- `patches/qt6-multimedia/0016-0026`: the depth series (0025 and 0026 are ORDER 411: a depth video recorded sideways or upside down is drawn the right way up, and the compositor path of a depth video is a test of the isolated Stereo KWin), rebased on the published stack (patches 0001 to 0015 and qt-mvhevc); `git format-patch` of branches `depth-6.11.2-stereo3d14` (0016 to 0024) and `order411-qt` (0025, 0026) of invent/github danielcamposramos/qtmultimedia over `b13-stack` (the published stack as commits).
- `patches/dragon/0002 to 0005, dragon-3d-video.po.patch`: branches `depth-stereo3d6-pkg` (0002 to 0004) and `order411-save-pkg` (0005) of danielcamposramos/dragon over `b5-stack` (the published +stereo3d5); the translations are the edition's `translations/dragon-3d-video.po.patch`.
- `changelog/*.items`: the changelog items, one paragraph per item.
- `next-source.sh PACKAGE PUBLISHED.dsc OUT [SYMBOLS]`: the next +lc1 source (`repo/lc-successor.py --in-place --overlay`): the published history stays a byte identical suffix of the new changelog, the toolkit is this tree's, and nothing else of debian/ changes but the patches, the series, the symbols file and the dependency texts the script names.
- `build.sh` and `build-in-container.sh`: the Lean Code build in `sparky-lc-migration:20261020` with the link and start gate against the published +lc1 build (`SPARKY_LC_ARCHIVE_CONFIG`, `SPARKY_LC_SCRATCH`), then `lean.release check-debs`.

## Order

1. `next-source.sh qt6-multimedia` then `build.sh qt6-multimedia`; the debs go into a flat repository: `apt-ftparchive packages . > Packages` and `apt-ftparchive -o APT::FTPArchive::Release::Origin="Sparky Stereo OS" release . > Release`. The Origin matters: the build container pins the edition's origin at 1001, and a flat repository without it loses to the published +13 (Dragon's build dependency on +14 then reads "not going to be installed").
   `build.sh` takes the published edition's .deb list as its 8th argument (the link gate resolves edition libraries, libavutil61 +stereo3d9 among them, from that snapshot as the publisher does; without it Debian's and deb-multimedia's higher-numbered 9.0.2-dmo4 wins and the gate rightly fails on av_multiview_real_to_double).
2. `next-source.sh dragon` then `build.sh dragon ... NEW_DIR` with that repository: dragon builds against qt6-multimedia-dev +stereo3d14.

## Dependencies added or changed

- qt6-multimedia Build-Depends: libstereo-dibr-dev (>= 1.9.0), from the edition's repository (1.12.0-5+lc1 published; checked with apt-cache policy in the build container).
- dragon: qt6-multimedia-dev, libqt6multimedia6 and qml6-module-qtmultimedia raised to 6.11.2-3+stereo3d14+lc1; Depends kde-cli-tools (kcmshell6) and kscreen (kcm_kscreen), which the Display Settings shortcut starts; both are Debian packages, checked with apt-cache policy.

## ORDER 411, group 2b

- `patches/dragon/0005`: Dragon offers to save the correction into the file; stereo-layer 1.13.0 (`stereo-layer-source.sh` makes its +lc1 source from the release tag of the fork clone, `build.sh stereo-layer` builds it) carries `stereo_mark_save` in libstereo-av. Dragon Depends on mkvtoolnix (mkvpropedit writes Matroska), and builds against libstereo-av-dev and libstereo-policy-dev 1.13.0.
- `dragon-3d-video.po.patch` holds 68 strings now: the 40 of the menu and window, and the 28 of the offer (all nine languages, English in the code). It was regenerated from the release catalogs, never edited by hand.
- Build order: stereo-layer 1.13.0 first (the debs go into the flat repository with qt6-multimedia's), then dragon.

## ORDER 411, group 2e

- `patches/qt6-multimedia/0027, 0028` (branch `order411-2e` of danielcamposramos/qtmultimedia over `order411-qt`): VideoOutput draws the views of a depth video on the GPU, the best way that keeps the frame rate (libstereo-dibr 1.15.0's ladder and timings), and the tests. qt6-multimedia Build-Depends libstereo-dibr-dev (>= 1.15.0).
- `patches/dragon/0007` (branch `order411-2e-pkg` of danielcamposramos/dragon over `order411-2c-pkg`): Automatic way of drawing in the 3D Video Settings window, bound to the video only until the person picks a warping or a gap filling. dragon 4:26.04.0-1+stereo3d9+lc1 Depends libstereo-layer1 (>= 1.15.0) and builds against libstereo-av-dev and libstereo-policy-dev (>= 1.15.0).
- Build order: stereo-layer 1.15.0 (`stereo-layer-source.sh FORK release-1.15.0 OUT`, `build.sh stereo-layer`), then qt6-multimedia (flat repository with the stereo-layer debs, `ROUND_SOURCES="stereo-layer"`; the source directory needs the orig tarball beside the .dsc), then dragon (flat repository with both).
- `next-source.sh qt6-multimedia PUBLISHED.dsc OUT symbols/qt6-multimedia-stereo3d14.symbols`: the two QVideoFrameFormat symbols +stereo3d14 adds to libqt6multimedia6.symbols; leaving the fourth argument out drops them (the first 2e source did, and the diff against the accepted +14 showed it).

## ORDER 411, step 2g

- `patches/qt6-multimedia/0030` (branch `order411-2g` of danielcamposramos/qtmultimedia over `order411-2f`): 10, 12 and 16 bit depth video on the GPU path at the source's depth (P010, P016, YUV420P10, YUV422P16, YUV444P16), the decoder's VA-API frames read where they are (QHwVideoBuffer::mapTextures through a QRhi sharing the drawing context, no copy to system memory), and VideoOutput::stereoDepthGpuMemory.
- `patches/dragon/0008` (branch `order411-2g` of danielcamposramos/dragon over `order411-2e`): the 3D Video Settings lists say beside a way that needs more of the GPU's memory than is free, from stereoDepthGpuMemory.
- stereo-layer 1.17.0 (`stereo-layer-source.sh FORK release-1.17.0 OUT`): the passes hold the source's depth (`stereo_dibr_gl_set_precision`), the layered depth-aided way at 1080p per eye peaks at 193 MB counted instead of 309 MB (the driver took 252 MB instead of 359 MB on an RTX 3060), and `stereo_dibr_way_fits()` is the one rule of the guard and of the controls' sentence. qt6-multimedia and dragon depend on libstereo-dibr-dev, libstereo-layer1, libstereo-av-dev and libstereo-policy-dev (>= 1.17.0).
- Build order as in group 2e: stereo-layer 1.17.0, qt6-multimedia (`ROUND_SOURCES="stereo-layer"`, fourth argument of next-source.sh the symbols file), dragon (`ROUND_SOURCES="stereo-layer qt6-multimedia"`).

## ORDER 411, step 2h

- `patches/qt6-multimedia/0031 to 0034` carry Qt's own change for NVDEC frames (not our code): `FFmpeg: Add CUDA hw-texture converter for NVDEC decode on Linux` (Tim Blechmann, qt/qtmultimedia dev c57f4af5ab, 2026-09-16, reviewed by Artem Dyomin), with the vendored ffnvcodec header it includes (`3rdparty: import ffnvcodec dynlink_cuda.h`, 2506a582c8) and the Vulkan helpers (`Multimedia: add QDebug support for VkResult and VAStatus`, fad9a642f0, the Vulkan part only: the VA-API part and the changes to the VA-API converter are dev's own and 6.11.2's converter differs). 0034 makes the converter's backend through its factory, as 6.11.2 constructs its backends. Not carried: the test library helper and tst_qcudatextureconverter, which need dev's test library. Upstream was searched first (Gerrit answered 403 to the lane; the GitHub mirror qt/qtmultimedia, dev branch, and its file histories were read).
- `patches/qt6-multimedia/0035 to 0041` (branch `order411-2h` of danielcamposramos/qtmultimedia over `order411-2g`): the drawn views go to the video sink as GL textures (no read back) when the sink draws with OpenGL, VideoOutput.stereoDepthRoute and stereoDepthReadBacks() (the stereo layer's presenter still reads the views back: told), and the imported frames' textures are made readable by the passes with the first frames of a stream sampled for a picture (the first VA-API import on the A10 read as zeros).
- stereo-layer 1.17.1 (`stereo-layer-source.sh FORK release-1.17.1 OUT`): stereo_dibr_way_memory() counts the picture, its depth and the views at the content's depth. qt6-multimedia and dragon depend on libstereo-* (>= 1.17.1).
- Build order as in step 2g, with stereo-layer 1.17.1 (the build used THREADS=4, BUILD_NAME_PREFIX=d411-build, ARCHIVE_DIR /mnt/build/depth-151/archive, the published edition's .deb list /mnt/build/depth-151/work/previous-siblings.txt).

## ORDER 411, step 2i

- `patches/qt6-multimedia/0039 to 0041` (branch `order411-2i` of danielcamposramos/qtmultimedia over `order411-2h`): NVDEC's P012 frames in the CUDA converter; the stereo layer draws the drawn views itself into an EGL window surface of the GPU (no read back, no copy of ours; wl_shm only where the driver has no surface of the depth, counted and said); the colour matrix of an untagged frame as Qt's own conversion has it; the compositor case reads both kinds of recorded surface.
- debian/copyright names the vendored ffnvcodec header (commit 591bfef of the coordinator).
- Build order unchanged (stereo-layer 1.17.1 is as in 2h).

## ORDER 411, step 2j

- `patches/qt6-multimedia/0042 to 0045` (branch `order411-2j` of danielcamposramos/qtmultimedia over `order411-2i`):
  - 0042: NVDEC's 4:4:4 frames are imported as three planes by the CUDA converter and the depth passes, not copied (YUV444P, YUV444P16, and FFmpeg 8's YUV444P10MSB and YUV444P12MSB);
  - 0043: a depth video no longer clears the stereo presenter at every frame (the output compared the stored input's format and packing with the drawn views'; the wl_shm control now delivers buffers on the A10);
  - 0044 and 0045: 12 to 16 bit video reaches the compositor at 16 bits: StereoSurface16Bit, a window surface of the driver where it has one, buffers the layer allocates (GBM, EGLImage, zwp_linux_dmabuf_v1) where it has none, wl_shm XBGR16161616 last, counted and said; the route says what was observed; the window surface has exactly the depth asked for (Mesa answered a request for 8.8.8 with a 10.10.10 config).
- qml6-module-qtmultimedia Depends libgbm1 and libwayland-egl1 (the stereo layer loads them; `next-source.sh` changes that one stanza of debian/control, each text exactly once).
- Build order unchanged (stereo-layer 1.17.1 is as in 2h and 2i).


## ORDER 453 and 453b: the players show a refused 3D declaration

- `patches/dragon/0009` (Dragon: a Kirigami InlineMessage over the video, warning type) and `../../upstream/qtmultimedia/plank-player/0003` (Plank Player: a banner in the theme's own neutral colours) show `stereoLayerFailure` of Qt Multimedia +stereo3d15 (patch 0046): "This video is shown flat: the desktop refused to show it in 3D (%1)." in the nine languages. Neither player has a stereo layer of its own: both sit on `VideoOutput`'s.
- dragon 4:26.04.0-1+stereo3d10+lc1 and plank-player 5.27.80+git20261005.f87e775-1+stereo3d3+lc1 depend on Qt Multimedia +stereo3d15.
- Build, from the published sources (`$R` the published tree, `$FLAT` a flat repository of the +stereo3d15 debs made with `dpkg-scanpackages -m . /dev/null > Packages` plus a `Release` that says `Origin: Sparky Stereo OS`, `$SIBS` the published edition's .deb list, one `/repo/pool/...` path per line):
  1. `next-source.sh dragon $R/pool/main/d/dragon/dragon_26.04.0-1+stereo3d9+lc1.dsc OUT` and `next-source.sh plank-player $R/pool/main/p/plank-player/plank-player_5.27.80+git20261005.f87e775-1+stereo3d2+lc1.dsc OUT` (the published orig tarball is copied beside each .dsc);
  2. `ROUND_SOURCES=qt6-multimedia build.sh dragon WORK OUT PREV $R ARCHIVE $FLAT $SIBS` (and `plank-player`). Without `ROUND_SOURCES` the link gate stops with "conflicting supplied package: libqt6multimedia6": the published +stereo3d14 and the +stereo3d15 of the flat repository are both supplied.
- Plank Player needs no build image of its own here: the Lean Code container builds it like Dragon (the old `plank-build:1` of `upstream/qtmultimedia/packaging/build-plank-player.sh` is history).
- A source is dated by this folder's last commit (ORDER 421b), so a commit in this folder moves the changelog date of the next build; the staged 453b build used SOURCE_DATE_EPOCH 1794262505 (commit 988b8ef1).

## Inspect a player source before rebuilding

Start from the archive's `.dsc`, Debian tarball and orig tarball, and inspect an unpublished successor separately.
In the packaging container, list `debian/patches/series` and the top changelog entry with `tar -xOf PACKAGE.debian.tar.xz debian/patches/series` and `tar -xOf PACKAGE.debian.tar.xz debian/changelog`, then unpack with `dpkg-source -x PACKAGE.dsc SOURCE`.
Check the `.dsc` checksums and the stage's `SHA256SUMS` before using either source.
The published patch bytes and changelog must remain unchanged in the successor: its series extends the published series, and its changelog ends with the published changelog byte for byte.

| Source | Player patches and successor additions |
| --- | --- |
| Dragon `+stereo3d9+lc1` to `+stereo3d10+lc1` | `upstream/qtmultimedia/dragon/0001`, `packages/spatial-video/patches/dragon-mvhevc.patch`, this folder's `patches/dragon/0002` through `0008`, and `dragon-3d-video.po.patch`; the successor adds `0009` |
| Plank Player `+stereo3d2+lc1` to `+stereo3d3+lc1` | `upstream/qtmultimedia/plank-player/0001` and `0002`; the successor adds `0003` and `0004` |

Paths in the table are relative to `sparky-os`, except the explicitly named paths in this folder.
The `upstream/dragonplayer` and `upstream/plank-player` folders are superseded recipes.
The accepted successor route is `next-source.sh` followed by this folder's `build.sh` for either player.
Changing `upstream/qtmultimedia/packaging/plank-player-debian/control` alone does not change that route: `next-source.sh` modifies the published control file with exact dependency replacements.
In `+stereo3d3+lc1`, both Qt Multimedia dependencies require `+stereo3d15~`; inspect the generated control file rather than inferring it from the older standalone packaging template.

For player follow-ups, inspect these boundaries in the unpacked source:

- Plank chooses the `org.kde.desktop` style in `app/main.cpp`, before loading `app/qml/main.qml`.
  The style's QML module is required at startup even though this main QML file has no literal `import org.kde.desktop` line.
- Plank's `app/qml/main.qml::onSourceChanged` resets `stereoInput` and `stereoSwapEyes` in the `+stereo3d3` source.
  That source has no resume-position or per-file settings store; `app/main.cpp` supplies the `PlankPlayer` organisation and application names for a store in the application's configuration location.
- Dragon's `src/qml/ControlsBar.qml::canOfferSave` already checks stereo content, the view, a local file and a changed packing or swap.
  Test the generated menu item's visibility with the menu open: a `Kirigami.Action` inside a Qt Quick Controls `Menu` can have `visible: false` while its generated item remains visible and enabled.
- Dragon's volume-wheel error is in `src/qml/PlayerPage.qml`, whose line changes when patches add content above it.
  Upstream [merge request 86](https://invent.kde.org/multimedia/dragon/-/merge_requests/86), Erich Seifert's `ae56fa67c9d5ff4742136a25b0071d18a4f7f047`, corrects the `audioOutput` reference and restores its binding after scrolling.
  Check the current upstream state before carrying it; preserve its author and the complete fix.
  The other two reported sites are `src/qml/OverlayPopup.qml` (`backgroundSource`) and `src/qml/IconToolButton.qml` (an optional tooltip assigned to a string).

Credits remain those of each source: Dragon names Max Howell, Ian Monroe and Harald Sitter in `src/main.cpp`; the overlay component names Marco Martin.
Plank Player's `app/main.cpp` names Aditya Mehra.

## Player follow-ups (ORDER 453c)

Dragon `4:26.04.0-1+stereo3d11+lc1` carries `0010` (the Save menu item itself and both entry points use `canOfferSave`), `0011` (Erich Seifert's complete MR 86), and `0012` (the popup reads its shader source; a button reads its action's tooltip or its own text).
Plank Player `5.27.80+git20261005.f87e775-1+stereo3d4+lc1` carries `0005` (per-file input corrections) and `0006` (the settings failure message in eight catalogues, with English in QML).
`next-source.sh` accepts Dragon +10 or +9 for +11, and Plank +3 or +2 for +4; prefer the accepted +10/+3 stage to keep its changelog history.
Both Plank packaging routes require `qml6-module-org-kde-desktop`, and both Qt Multimedia runtime dependencies require +15.

Plank has no resume store and does not link KConfig.
It uses QtCore's QSettings with its existing organisation and application names, `PlankPlayer`, so its configuration file is `$XDG_CONFIG_HOME/PlankPlayer/PlankPlayer.conf` (normally `~/.config/PlankPlayer/PlankPlayer.conf`).
The group is `[StereoVideo]`; SHA-256 of the fully encoded file URL is the swap key, and that hash plus `.input` is the packing key, matching Dragon's scheme.
False swap and automatic packing remove their entries.
Only menu choices write settings; loading another file reads them and never copies the previous file's choices.
A settings read/write failure is visible in the banner, with the file named; media files and their metadata are never changed by Plank.
