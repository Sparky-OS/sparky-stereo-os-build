# The per-file 3D choice in the album programs (ORDER 551b, continuing ORDER 551)

stereo-layer 1.19.0-1+lc1, koko 26.04.0-1+stereo3d2+lc1, kphotoalbum 6.2.0-1+stereo3d2+lc1 and digikam 4:9.1.0-1+stereo3d4+lc1 (with showfoto).

A person's choice for one file (the input packing chosen by hand, Not 3D, the swap of the eyes) is kept once, in the stereo layer's store, and every program on the layer shows the file by it.
ORDER 551 put Dolphin, its thumbnailers and Gwenview on it; this order adds Koko, KPhotoAlbum, digiKam and Showfoto.
The file is never written unless the person chooses "Save the correction into the file".

Design followed (Daniel's words, as recorded):
- Never touch the user's file (2026-10-23): "never touch the user file, it's the same place where the continue playback is saved (as another indicator per file)"; "change it to offer the user to save to the file"; "when accepted, it's apply to the file and leave the option unmarked".
- The definitive swap is the output's (2026-10-23): "two swap eyes true, one on the output, the other per file, the only "definitive" swap is on the output". Koko's swap was one for every picture of its view; it is the file's now.
- No correction on 2D content (2026-10-23, on a swap for a 2D video): "of course no". A picture shown flat is offered no swap and no save.
- Nothing fails silently (2026-11-01): "either it works or not and the user must know".

## What changed in each

- **stereo-layer 1.19.0**: the QML form of the per-file menu, in the layer itself, so any QML program can use it: the types `FileChoice` and `FileChoiceMenu` of `org.sparky.stereo`. The widgets' `Stereo::FileChoiceMenu` and the QML type are two faces of one private list (the entries, their words, the writes to the store), so both offer every packing in the same words, from the same catalogues. `StereoPicture.refresh()` decodes again on `changed()`; a program with a `FileChoice` also keeps a file's choice with it on a rename or move.
- **koko**: the image view's 3D menu shows the layer's QML menu; the page keeps which eye is shown. The page's own list (five packings), its anaglyph pair and its swap, which applied to every picture, are gone into the file's choice.
- **kphotoalbum**: the viewer's 3D menu shows `Stereo::FileChoiceMenu`; the viewer keeps which eye is shown.
- **digikam**, **showfoto**: the 3D menu of the album preview, the light table, the editor and the slide show shows `Stereo::FileChoiceMenu`; the program keeps its own lasting view (Stereo, one eye, Not 3D for every picture, in digikamrc). The editor decodes through the layer with the file's path. digiKam's own rename and move of files, folders and albums tell the store.

None of the three kept per-file state of its own (their choices were the session's, digiKam's view is the program's), so there is nothing to carry into the store.

## Files

- `patches/koko-shared-per-file-choice.patch`, `patches/kphotoalbum-shared-per-file-choice.patch`, `patches/digikam-shared-per-file-choice.patch`: the code, appended to each published series.
- `patches/koko-stereo-translations-de-es.patch`, `patches/kphotoalbum-stereo-translations-de-es.patch`: German and Spanish for the eleven sentences each 3D menu keeps (the published `stereo-translations.patch` of each has the other seven languages); last in the series. The per-file entries are the layer's and come from its catalogues, so these programs add no sentence.
- `changelog/*.items`: the changelog items, one paragraph per item.
- `retired-stereo-imports/PACKAGE`: the stereo functions a new version stops calling on purpose, each with its reason, installed as `debian/sparky-lean-retired-stereo-imports` (`lean/archive.md`).
- `next-source.sh PACKAGE PUBLISHED.dsc OUT`: the next +lc1 source (`repo/lc-successor.py --in-place --overlay`): the published history stays a byte identical suffix of the new changelog, and nothing else of debian/ changes but the patches, the series and the layer's version in Build-Depends. The published rules of all three already pass `-DCMAKE_REQUIRE_FIND_PACKAGE_StereoLayer=ON`; the script stops if they do not.
- `round.sh WORK STEREO_LAYER_CLONE REV PUBLISHED_TREE ARCHIVE_DIR STAGE_551 [STEP...]`: every build in order, each through `../depth-source/build.sh` (Lean Code, the link and start gate, `lean.release check-debs`), collected in a flat repository with the edition's Origin for the next one.

## Order, and why

1. stereo-layer 1.19.0 through the gate, under `SPARKY_BUILD_PROFILES=nocheck` as in ORDER 551. `libstereo-layer1` depends on `kimageformat6-plugins (>= 6.30.0-1+stereo3d6)`, and the plugin +stereo3d7 was built and staged by ORDER 551: the round's repository starts with that round's staged packages (copied, never linked), so no bootstrap is needed here. The link gate compares the new layer with ORDER 551's 1.18.0, the build it follows.
2. koko and kphotoalbum, small builds.
3. digikam, the large one, last.

## Dependencies added or changed

- stereo-layer: `libstereo-layer1` Depends on `qml6-module-qtquick-controls` and `qml6-module-qtqml-models`, which `FileChoiceMenu.qml` imports, and the source Build-Depends on both (the QML compiler reads their type descriptions). Both are in the edition's repository (qt6-declarative +stereo3d2), checked with `apt-cache policy` in the build image.
- koko, kphotoalbum, digikam: `libstereo-layer-dev (>= 1.19.0)` in Build-Depends (from 1.4.0, 1.4.0 and 1.0.2); the edition's own package, built in step 1.
- No other package name is new.
