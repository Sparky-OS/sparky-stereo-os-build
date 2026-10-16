# Translations carried by the edition

KDE takes translations only through its translation teams, never as commits to a project (invent.kde.org rejects them: "Translation contributions must be submitted according to https://community.kde.org/Get_Involved/translation"). So our KDE forks carry no `po/` changes. The edition's translated strings for the stereo features live here as patches, applied when Sparky packages are built.

**The required set (Daniel, 2026-10-11):** Polish, Brazilian Portuguese, French, Japanese, Korean and Chinese (Simplified and Traditional), beside the English in the code. The full rule is in SPARKY-STEREO-OS.md, "Languages".

- `kwin-virtual-3d-modes.po.patch`: KWin's virtual 3D mode strings.
- `kscreen-virtual-3d-modes.po.patch`: the display settings' toggles and labels.
- `kscreen-stereo-pairs.po.patch`: the display settings' stereo pairs.
- `krdp-throw.po.patch`: KRdp's headset discovery and approval named Throw: its strings in eight languages (po/, with a new Japanese catalog) and the discovery entry's and notification's translated names; from the phone lane's commits 24465ba and 646fb0b, whose code half is invent danielcamposramos/krdp phone-throw 8a3a79dbfc.
- `kwin-throw-view.po.patch`: KWin's headset view helper renamed Throw view: its 19 strings in eight languages (po/) and its launcher's translated Name and Comment; from the phone lane's commit 3de53c9, whose code half is invent danielcamposramos/kwin phone-throw c97fc23e3f.
- `kdeconnect-kde-throw.po.patch`: KDE Connect's virtual monitor plugin, the two Throw errors (identity, start), in all eight translated languages (pl, pt_BR, fr, de, ja, ko, zh_CN, zh_TW); from the phone lane's commit af53494, whose source half is invent danielcamposramos/kdeconnect-kde stereo3d-phone e1b0792b5.

Today these patches carry pl, pt_BR, fr and ja; ko, zh_CN and zh_TW are still being added.

Upstream, the same strings go to each language's KDE translation team once the features are merged and their strings are in KDE's translation system (Daniel's step). English stays in the code, as KDE expects.
