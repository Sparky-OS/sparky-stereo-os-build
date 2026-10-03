# Translations carried by the edition

KDE takes translations only through its translation teams, never as commits to a project (invent.kde.org rejects them: "Translation contributions must be submitted according to https://community.kde.org/Get_Involved/translation"). So our KDE forks carry no `po/` changes. The edition's Polish and Brazilian Portuguese strings for the stereo features live here as patches, applied when Sparky packages are built:

- `kwin-virtual-3d-modes.po.patch`: KWin's virtual 3D mode strings, pl and pt_BR.
- `kscreen-virtual-3d-modes.po.patch`: the display settings' toggles and labels, pl and pt_BR.

Upstream, the same strings go to KDE's Polish and Brazilian Portuguese translation teams once the features are merged and their strings are in KDE's translation system (Daniel's step). English stays in the code, as KDE expects.
