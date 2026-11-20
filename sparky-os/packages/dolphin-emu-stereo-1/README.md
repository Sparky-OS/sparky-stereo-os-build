# dolphin-emu-stereo-1 (ORDER 39)

Dolphin 2609.b+dfsg-1+stereo3d1+lc1, built from Debian's own source package (2609.b+dfsg-1, the release Debian testing ships) with two patches, `patches/stereo-1-one-declared-output.patch` and `patches/stereo-2-translations.patch`, made from branch `order39` of the edition's Dolphin fork (commits 9b9a77e to 0d9e0eb on Debian's patched tree 2b493fa).

Design followed:
- /K3D/CLAUDE.md: "Every source ... hands KWin full side by side: the two eyes as separate complete pictures, side by side, left eye first, declared once"; "A program never stretches or squeezes an eye"; "a program that renders its own 3D scene offers no swap". The one output is the declared pair; Dolphin's top and bottom, anaglyph, quad buffer, passive, half-width eyes and eye swap are not built.
- Daniel, 2026-11-19 (one separation, one place; "I accepted internal 3D programs settings"): Dolphin's own Depth and Convergence, the per-game Depth Percentage, Convergence and Monoscopic Shadows, and their hotkeys are upstream's code with upstream's defaults; nothing of ours reads the desktop's limits or scales the separation.
- stereo-integrations-auto-enable (Daniel, 2026-10-14), as PyMOL's edition build has it: Enable 3D is on by default; a desktop without the pair shows 2D and says nothing unless the person turned 3D on; a renderer or Vulkan surface that cannot give two views is told.

How the pair is made:
- OpenGL: `DolphinQt/StereoDeclare.cpp` declares the render window (or the render widget, a child of the main window) through libstereo-declare; Stereo KWin makes the X11 window two views wide and the presenter draws the left eye in the left half and the right eye in the right half, each at the eye's own size.
- Vulkan: the swapchain has two image layers; Mesa's X11 presentation (or its Vulkan stereo layer over another driver) packs them into one picture and declares the window, which stays one view wide. A Vulkan surface that offers one layer is told. Mesa up to +stereo3d28 gives a surface half its window's width at random (Mesa patch 0047, +stereo3d29): with it each eye was drawn at half the width in about four sessions of ten.
- The interface and the on-screen messages are drawn in both eyes at the same place.
- The no-GUI front end declares nothing: it shows 2D and says so when the person turned 3D on.

Build: `build.sh WORK PREVIOUS_DIR SOURCE_DIR IMAGE` with `SPARKY_REPO_DIR` and `SPARKY_LC_ARCHIVE_DIR` set (see the header of build.sh); `build-in-container.sh` runs inside. Role line: `lists/emulation-3d.list` already names dolphin-emu.
