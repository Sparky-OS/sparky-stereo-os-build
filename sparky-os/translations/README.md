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
