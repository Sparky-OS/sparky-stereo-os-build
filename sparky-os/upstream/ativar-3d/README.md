# The 3D switch is "Ativar 3D" in Brazilian Portuguese (ORDER 586)

Daniel's decision of 2026-11-15 (brief of ptbr-ativar-3d-586): the program switch "Enable 3D" reads "Ativar 3D" in Brazilian Portuguese in everything the edition ships (memory same-ideas-same-names-everywhere, 2026-11-04: one idea keeps one name in every program and every language).
The stereo layer (`po/pt_BR/stereo-layer_qt.po`) and sView (`lang/portuguesebr/…​.lng`) already say "Ativar 3D"; the players Dragon Player and Haruna said "Ativar o 3D".
Only the one word "o" is removed in pt_BR; no other string changes in any language, and pt (Portugal) is another language: nothing there.

| Program | How the next version is made | Patch |
|---|---|---|
| dragonplayer 4:26.04.0-1+stereo3d13+lc1 | `mk-successors.sh` (lc-successor --in-place --overlay) on dragon_26.04.0-1+stereo3d12+lc1 | patches/dragon-0015 |
| haruna 1.8.1-1+stereo3d6+lc1 | `mk-successors.sh` | patches/haruna-0008 |

The same fix is already in the catalogues the recipes ship: `sparky-os/translations/dragon-3d-video.po.patch` and its copy in `sparky-os/packages/depth-source/patches/dragon/` now write "Ativar 3D" for pt_BR.
Haruna's catalogue lives in its own source until upstream takes it (patch 0006), so only this recipe's patch 0008 corrects it.

The other players and viewers (Plank Player, Bino, VLC, sView, Gwenview, Koko, KPhotoAlbum, digiKam, Showfoto, Dolphin, Kamoso) have no translated form of the switch, so there is nothing to change there.
