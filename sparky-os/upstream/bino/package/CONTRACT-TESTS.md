# Native strip and metadata regression

Build both BINO_STEREO_DESKTOP settings.
The ON build uses libstereo-av's content-inspection API and libstereo-declare 1.7 for native child placement.
The OFF build retains the upstream output modes and their conversion tests.

Run tests/strip-contract with a new isolated KWin session for each case.
Keep the ffprobe-absent, previous player, swapped-eye, plain mono, containment, and one-resize controls.
Use tests/frame-path/source.cpp for source precedence and per-file corrections, buttons.cpp/buttons.py for normal and hovered round backings, and the retained import, fallback and repaint tests.
Repeat the native source matrix from the installed package.

For Lean Code's symbol comparison, use an unprojected build of the same authored candidate as the pre-lc baseline, then run the payload and missing-library negative controls.
Also retain the comparison with the previous published build.
The detector migration intentionally removes Stereo::Video's nameTag, sideBySideByShape, views and matroskaPlane imports from the edition executable; stereo_content_inspect replaces their metadata path.
The old-release import-retention check flags that migration and requires publication review; do not hide it or retain dead calls merely to keep symbols.
