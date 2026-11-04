# Translations carried by the edition

KDE takes translations only through its translation teams, never as commits to a project (invent.kde.org rejects them: "Translation contributions must be submitted according to https://community.kde.org/Get_Involved/translation"). So our KDE forks carry no `po/` changes. The edition's translated strings for the stereo features live here as patches, applied when Sparky packages are built.

**The required set (Daniel, 2026-10-11; German since 2026-10-15):** Polish, Brazilian Portuguese, French, German, Japanese, Korean and Chinese (Simplified and Traditional), beside the English in the code.

- `kwin-virtual-3d-modes.po.patch`: KWin's virtual 3D mode strings.
- `kinfocenter-stereo3d.po.patch`: KInfoCenter's Stereo 3D and Deep Colour page, in French.
- `krdc-catch.po.patch`: KRDC's Catch receiver (the Kirigami frontend that catches a Throw on Plasma Mobile and the desktop, ORDER 124): its eight messages and translated launcher entries in eight languages; from the phone lane, on invent danielcamposramos/krdc stereo3d b3cd02d484.
- `krdp-throw.po.patch`: KRdp's headset discovery and approval named Throw: its strings in eight languages (po/, with a new Japanese catalog) and the discovery entry's and notification's translated names; from the phone lane's commits 24465ba and 646fb0b, whose code half is invent danielcamposramos/krdp phone-throw 8a3a79dbfc.
- `kwin-stereo-depth.po.patch`: KWin's 3D Depth page in System Settings (the eased level changes and the linked focus and raise delays, ORDER 145), in all eight translated languages; from the kwin-stereo-effects lane (KWin +stereo3d26).
- `kwin-throw-view.po.patch`: KWin's headset view helper renamed Throw view: its 19 strings in eight languages (po/) and its launcher's translated Name and Comment; from the phone lane's commit 3de53c9, whose code half is invent danielcamposramos/kwin phone-throw c97fc23e3f.
- `kdeconnect-kde-throw.po.patch`: KDE Connect's virtual monitor plugin, the two Throw errors (identity, start), in all eight translated languages (pl, pt_BR, fr, de, ja, ko, zh_CN, zh_TW); from the phone lane's commit af53494, whose source half is invent danielcamposramos/kdeconnect-kde stereo3d-phone e1b0792b5.
- `haruna-3d-video.po.patch`: Haruna's 3D Video menu and settings page, the published menu's strings and the depth options (97 strings), in all eight translated languages; from the depth lane (ORDER 151, step R part 2), whose code half is invent danielcamposramos/haruna stereo3d 5a3a6576. Every catalog passes `msgfmt -c`; fr, ja, ko, zh_CN and zh_TW still need a second-model check.

Today these patches carry pl, pt_BR, fr and ja; ko, zh_CN and zh_TW are still being added.

Upstream, the same strings go to each language's KDE translation team once the features are merged and their strings are in KDE's translation system (Daniel's step). English stays in the code, as KDE expects.
- `kf6-kfilemetadata-stereo3d.po.patch`: KFileMetaData's added stereo property label ("Stereo 3D Layout"), currently in French; from `kf6-kfilemetadata 6.30.0-1+stereo3d2`, source `src/propertyinfo.cpp:92`.
- `powerdevil-graphics-link.po.patch`: the Graphics button in Power Management's related pages (its name and accessible name), in the eight translated languages; code half is `sparky-os/power-idle/patches/powerdevil/graphics-page-link.patch` (ORDER 227). A first draft with AI assistance, pending review by native speakers.
- `kwin-wallpaper-cost.po.patch`, `plasma-desktop-wallpaper-cost.po.patch`, `plasma-workspace-wallpaper-cost.po.patch` and `kscreenlocker-wallpaper-cost.po.patch` (ORDER 292): what a sunk wallpaper loses at the sides on a screen in a 3D mode ("10 pixels of the wallpaper's width will be lost to the sunk effect, 5 at each side", with KWin's live number) and Daniel's sentence on videos with pop effects, in the eight translated languages, for KWin's 3D Depth page (`kcm_kwinstereodepth`), the desktop's wallpaper page (`plasma_shell_org.kde.plasma.desktop`), System Settings' Wallpaper page (`kcm_wallpaper`) and the lock screen's Appearance page (`kcm_screenlocker`). Each is appended to the catalog as the package builds it: KWin's after `kwin-stereo-depth.po.patch` in its series, the other three to the 6.7.4 tarballs' catalogs. Every catalog passes `msgfmt -c`. A first draft with AI assistance, pending review by native speakers. Carry each one last in its package's series, then retire it as 2120e50 did once the published source carries it.
- `kf6-kio-gpu-launch.po.patch` (ORDER 346g): the seven messages of a launch that does not start because the Graphics page's GPU cannot be applied (the program that was not started, and why sparky-stereo-gpu-env could not apply its GPU: it failed, crashed, could not be started or did not answer), in the eight translated languages, for KIO's `kio6` catalog; code half is `sparky-os/packages/kf6-kio/patches/EDITION-ONLY-start-no-application-whose-GPU-cannot-be-applied.patch`. The wording follows the published lines of sparky-stereo-gpu-run. Every catalog passes `msgfmt -c`. A first draft with AI assistance, pending review by native speakers. Carried last in kf6-kio's series by its build.sh.
- `command-not-found-messages.po.patch` (ORDER 252b, J15): the messages Debian's command-not-found 23.04.0 prints that its catalogs leave untranslated in the nine languages: ten in pt_BR and zh_TW (its main header, "Command '%(command)s' not found, but can be installed with:", among them) and three in ja; pl, fr, de, ko and zh_CN are complete. Not a KDE catalog: command-not-found is Ubuntu's program, translated on Launchpad, so these are an offer for its translators there. Carried after `sparky-renamed-commands.patch` in command-not-found's series by its build-in-container.sh. Every catalog passes `msgfmt -c`; translated by Claude for Daniel Ramos (Capitain Jack), pt_BR for Daniel's review.

## Which package carries each patch (ORDER 391)

A patch ships only when a build names it last in the package's `debian/patches/series` (dpkg-source(1): the series "lists all patches that have to be applied"; a patch no series names never ships).
Six of these patches were made "for the next package" and no build applied them.
`sparky-os/packages/catalogue-rebuilds/` is the build that names one: the published source back to its plain form, the patch last in the series, one changelog entry.
`sparky-os/tests/translations-shipped.py` keeps it from happening again: for every patch here it reads the newest built package of its source and fails on any added string the package's catalogues lack.

| Patch | Source package | Carried by |
| --- | --- | --- |
| `kalgebra-stereo3d.po.patch` | kalgebra | 4:26.04.0-1+stereo3d3 |
| `kalzium-stereo3d.po.patch` | kalzium | 4:26.04.3-1+stereo3d5 |
| `kubrick-stereo3d.po.patch` | kubrick | 4:26.04.0-1+stereo3d3 |
| `kinfocenter-stereo3d.po.patch` | kinfocenter | 4:6.7.4-1+stereo3d2 |
| `kf6-kfilemetadata-stereo3d.po.patch` | kf6-kfilemetadata | 6.30.0-1+stereo3d5 |
