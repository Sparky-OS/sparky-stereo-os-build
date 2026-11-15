# The album programs' own Enable 3D, and digiKam's carries told (ORDER 551c, continuing ORDER 551b)

stereo-layer 1.19.2-1+lc1, gwenview 4:26.04.0-1+stereo3d11+lc1, koko 26.04.0-1+stereo3d3+lc1, kphotoalbum 6.2.0-1+stereo3d3+lc1 and digikam 4:9.1.0-1+stereo3d5+lc1 (with showfoto).

A program's 3D options in the edition are "enable 3D, render resolution per eye, and a shortcut to Display Settings", and a media program adds the input corrections of each file (CLAUDE.md, the contract).
ORDER 551b left the album programs with two entries called "Not 3D": the file's, an input correction kept in the shared per-file store for every program, and the program's own, which shows every picture flat.
The second is the program's "Enable 3D", switched off.
The stereo layer now has it once, with one wording in the ten languages (Stereo::Enable3DAction for a widgets program, Enable3DAction in org.sparky.stereo for a QML program), the words Haruna and sView ship for the same option.
Each program keeps how long it lasts, as published: the session in Gwenview, Koko and KPhotoAlbum, its settings in digiKam and Showfoto.
Alt+Shift+N is that switch in all five.

Design followed (Daniel's words, as recorded):
- Same ideas, same names (2026-11-04): "if we can bake the same ideas with the same names in all technologies involved"; never a second name for an idea that has one.
- Never touch the user's file (2026-10-23): the per-file choice lives in the program's per-file state; the switch writes nothing to it.
- Nothing fails silently (2026-11-01): "either it works or not and the user must know". digiKam's own rename that cannot carry a stored choice is told to the person, not only logged.
- Ten languages for every sentence a person reads (2026-10-11, 2026-10-15, 2026-11-10).

The main session's reading, told to Daniel on 2026-11-15 and not his words: the per-file "Not 3D" is an input correction; the program's switch that shows everything flat is the contract's "enable 3D", switched off.

## Files

- `patches/gwenview-enable-3d.patch`, `patches/koko-enable-3d.patch`, `patches/kphotoalbum-enable-3d.patch`: each program's switch on the layer's Enable 3D.
- `patches/digikam-enable-3d-and-told-carry.patch`: the same for digiKam and Showfoto; a carry that fails told from the main thread; a folder moved to another device carries its files' choices.
- `patches/digikam-stereo-hole-on-the-layers-rectangle.patch`: the canvas item's stereo hole on the layer's own rectangle, in device pixels: Showfoto's row of desktop at 125 % (ORDER 576's finding) is gone.
- `../../translations/digikam-stereo3d.po.patch`: digiKam's twelve 3D sentences in nine languages, last in its series.
- `changelog/*.items`: the changelog items, one paragraph per item.
- `next-source.sh PACKAGE GIVEN.dsc OUT`: the next +lc1 source (`repo/lc-successor.py --in-place --overlay`) of gwenview's published +10 or of ORDER 551b's staged koko +2, kphotoalbum +2 and digikam +4.
- `round.sh WORK STEREO_LAYER_CLONE REV PUBLISHED_TREE ARCHIVE_DIR STAGE_551B STAGE_576 [STEP...]`: every build in order through `../depth-source/build.sh`; `BUILD_WORK` puts the build folders on another disk.

## Order, and why

1. stereo-layer 1.19.2 through the gate (`SPARKY_BUILD_PROFILES=nocheck`, as in ORDER 551 and 551b). It replaces both staged layers, 1.19.0 (ORDER 551b) and 1.18.1 (ORDER 576), and is 1.19.1 of the stereo-layer main branch with Enable3DAction and the QML StereoPicture's hole on whole device pixels (Koko's column of desktop at 125 %, ORDER 576's finding).
2. gwenview, koko and kphotoalbum against it.
3. digikam, the large one, last: it needs the floor plus about 35 GB free at its start (ORDER 551b's measurement).

The round's repository starts with ORDER 576's dolphin +8 (copied), so the installed proofs have the whole set; the link gate compares each source with its published build.

## Dependencies added or changed

- gwenview, koko, kphotoalbum, digikam: `libstereo-layer-dev (>= 1.19.2)` in Build-Depends (from 1.18.0, 1.19.0, 1.19.0 and 1.19.0); the edition's own package, built in step 1.
- No other package name is new.
