# kscreen (Display Settings) recipe

Display Settings (`kcm_kscreen`) is KDE's page; the edition adds the 3D modes, the stereo pair, depth, timing, glasses, the eye swap and the extra menus.

## Where the added strings' translations live

- **The code half** is in `patches/` (`stereo-and-anaglyph-resolution.patch`, `s9-*`, `s11-*`, `s12-*`, and the published source's own series).
- **The eight-language translations of the 3D strings are not in this repository.** They live only in the published source package, in `debian/patches/`: `kscreen-stereo.po.patch` (56 strings in pl, pt_BR, fr, de, ja, ko, zh_CN, zh_TW), `kscreen-glasses.po.patch`, `kscreen-swap-eyes.po.patch`, `kscreen-pair-labels.po.patch`, `kscreen-arrangement-view.po.patch`, `kscreen-dp-frame-sequential.po.patch` and `kscreen-wdisplays-menus.po.patch`. `sparky-os/translations/` still holds the last three (with Spanish added), but not the first four; commit 2120e503b retired them from the tree because stereo3d8 carried them.
- **Every successor must carry them.** A successor is made from the published source (`prepare-source-NN.sh` with `lc-successor.py --in-place --overlay`), and the overlay's `patches/series` is the whole new series: it must name each of those `.po.patch` files, as `overlay-stereo3d13/patches/series` does (line 3 and the three after `s9-0006`). Dropping a line from the series drops that language's strings from the next package with no error.
- **Spanish** is `sparky-os/translations/kscreen-spanish-display-settings.po.patch` (100 strings, ORDER 507b), copied byte for byte into `overlay-stereo3d14/patches/` and named last in its series. Its 37 strings from `arrangement-view`, `dp-frame-sequential` and `wdisplays-menus` also stand as Spanish hunks in the tree copies of those patches: a build that applies the tree copies instead of the published ones must drop those 37 from this file, or the catalogue gets each twice (msgfmt refuses the duplicate).

## The check

`python3 -I sparky-os/tests/translations-shipped.py --only kscreen-spanish-display-settings.po.patch STAGE` fails on any added string the built package's `.mo` lacks. To see what a built package answers in a language, read `usr/share/locale/LL/LC_MESSAGES/kcm_kscreen.mo` with Python's `gettext.GNUTranslations` (see skills `edition-packaging`, adding-a-required-language).
