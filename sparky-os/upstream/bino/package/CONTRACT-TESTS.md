# Native strip and metadata regression

Build both BINO_STEREO_DESKTOP settings.
The ON build uses libstereo-av's content-inspection API and libstereo-declare 1.7 for native child placement.
The OFF build retains the upstream output modes and their conversion tests.

Run tests/strip-contract with a new isolated KWin session for each case.
Keep the ffprobe-absent, previous player, swapped-eye, plain mono, containment, and one-resize controls.
Use tests/frame-path/source.cpp for source precedence and per-file corrections, buttons.cpp/buttons.py for normal and hovered round backings, and the retained import, fallback and repaint tests.
Repeat the native source matrix from the installed package.

Run hint-fixtures.py and hints.cpp for unmarked filename and frame-shape inference, misleading filenames on declared sources, explicit mono, and correction priority.
Run the native sample and display-shape checks on guessed sources too, including non-unit SAR with a half-view filename hint.

Run Lean Code check-debs and check-link against published bino 2.8-1+stereo3d3+lc1, without an import-retention allowance.
The shared nameTag, sideBySideByShape, views and matroskaPlane helpers remain live fallback paths below declared metadata.
Keep the missing-marker, missing-library and swapped-eye negative controls.
