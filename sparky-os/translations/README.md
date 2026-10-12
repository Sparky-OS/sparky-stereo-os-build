# Translations carried by the edition

KDE takes translations only through its translation teams, never as commits to a project (invent.kde.org rejects them: "Translation contributions must be submitted according to https://community.kde.org/Get_Involved/translation"). So our KDE forks carry no `po/` changes. The edition's translated strings for the stereo features live here as patches, applied when Sparky packages are built.

**The required set (Daniel, 2026-10-11):** Polish, Brazilian Portuguese, French, Japanese, Korean and Chinese (Simplified and Traditional), beside the English in the code. The full rule is in SPARKY-STEREO-OS.md, "Languages".

- `kwin-virtual-3d-modes.po.patch`: KWin's virtual 3D mode strings.
- `kscreen-virtual-3d-modes.po.patch`: the display settings' toggles and labels.
- `kscreen-stereo-pairs.po.patch`: the display settings' stereo pairs.

Today these patches carry pl, pt_BR and fr; ja, ko, zh_CN and zh_TW are still being added (queue item 46).

Upstream, the same strings go to each language's KDE translation team once the features are merged and their strings are in KDE's translation system (Daniel's step). English stays in the code, as KDE expects.
