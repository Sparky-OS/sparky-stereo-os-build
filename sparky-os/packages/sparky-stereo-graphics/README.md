sparky-stereo-graphics
The Graphics page of System Settings, Hardware: every graphics processor of the computer, the one that draws the desktop, and where each kind of program draws.

Copyright (C) 2026 Daniel Ramos (Capitain Jack), see copyright file.

This program is free software: you can redistribute it and/or modify it
under the GNU General Public License, version 3 or any later version.

Dependencies:
-------------
KDE Frameworks 6 (KConfig, KCMUtils, KI18n, KService, Kirigami), Qt 6 (Quick, DBus)
Recommended: switcheroo-control, power-profiles-daemon, hwdata

Build:
-------------
OUT=/path/in/workspace/pending-pack ./build.sh (inside a Debian container with KF6 development packages; node-acorn and python3-yaml for Lean Code)

Install:
-------------
su
apt-get install ./sparky-stereo-graphics_0.1.0_amd64.deb

Uninstall:
-------------
su
apt-get purge sparky-stereo-graphics

What the page shows and changes
-------------
- Graphics processors: one card per GPU (name from the PCI database, integrated or discrete, driver, the screens attached with their names from the EDID, what is placed on it now). A third card appears when a third GPU is installed. A chip that only shows a picture (a server board's BMC) is listed and never offered; a GPU the account may not open is listed with a hint.
- Main desktop GPU: Automatic (the GPU with the laptop panel, else the one with most screens) or any GPU that can render. It is written to ~/.config/sparky-stereo-graphicsrc and becomes KWIN_DRM_DEVICES at the next login (/etc/xdg/plasma-workspace/env/sparky-stereo-graphics.sh); the page says so and says which GPU the running session uses. A KWIN_DRM_DEVICES set by hand in ~/.config/plasma-workspace/env wins, and the page warns.
- Where programs draw: players, games, browsers and other programs, each Automatic, Integrated, Discrete or one GPU. Automatic follows the power profile: power saver the integrated GPU, performance the discrete GPU, balanced the GPU that draws the desktop.
- Programs: one list of menu entries, each "same as its group", "the other GPU" or "the main GPU". It is KDE's own PrefersNonDefaultGPU key in the person's copy of the entry (the same setting as Run Using Dedicated Graphics, written the way KMenuEdit writes it); there is no second list. A copy the page made follows the system entry when a package updates it, until the person edits it; an unchanged copy is deleted when the setting goes back to "same as its group".
- GPU power: power-profiles-daemon's GPU actions (amdgpu_dpm, amdgpu_panel_power) as switches; they are shown with one GPU as well.
Nothing is written until Apply. Defaults clears the main GPU and the render choices.

Commands
-------------
sparky-stereo-gpu-env: what the page decides, for programs that start programs (--category, --app, --choice, --profile, --print, --shell, --session, --list, --json).
sparky-stereo-gpu-run [--category C | --app ID] COMMAND: starts a program on its GPU; in Steam, set a game's launch options to `sparky-stereo-gpu-run --category games %command%`. It never stops a program from starting.

Tests
-------------
autotests: GPU listing from sysfs fixtures (one GPU, the A10's two AMD, the workstation's AMD and NVIDIA, a BMC board, three GPUs), saved choices, the power-profile mapping, the application list through KDE's own KService, the command line and the session script (with the edition's own primary-gpu script after it), the page and its QML on four machines, the power switches against a stand-in power-profiles-daemon on a private bus, and the translations of the nine languages.
