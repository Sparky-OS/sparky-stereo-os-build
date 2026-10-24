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
apt-get install ./sparky-stereo-graphics_0.2.2_amd64.deb

Uninstall:
-------------
su
apt-get purge sparky-stereo-graphics

What the page shows and changes
-------------
- Graphics processors: one card per GPU (name from the PCI database, integrated or discrete, driver, the screens attached with their names from the EDID, what is placed on it now). A third card appears when a third GPU is installed. A chip that only shows a picture (a server board's BMC) is listed and never offered; a GPU the account may not open is listed with a hint.
- Main desktop GPU: Automatic (the GPU with the laptop panel, else the one with most screens) or any GPU that can render. It is written to ~/.config/sparky-stereo-graphicsrc and becomes KWIN_DRM_DEVICES at the next login (/etc/xdg/plasma-workspace/env/sparky-stereo-graphics.sh); the page says so and says which GPU the running session uses. A KWIN_DRM_DEVICES set by hand in ~/.config/plasma-workspace/env wins, and the page warns.
- Where programs draw: players, games, browsers and other programs, each Automatic, Follow the power profile, Integrated, Discrete or one GPU. Automatic is split by kind (Daniel, 2026-10-24): players, games and any program started in 3D go to the GPU measured best on this machine whatever the power profile, on battery too (the drops on the GPU that drives the screens are "avoidable by default, with the user choice imperating over it"); without a measurement that is the discrete GPU. Browsers follow the power profile: power saver the integrated GPU, performance the discrete GPU, balanced the GPU that draws the desktop. Other programs (Dolphin, Kate, System Settings) stay on the GPU that draws the desktop in every profile. Follow the power profile keeps the profile in charge for any kind. The person's choice always wins. The kind comes from the entry's Categories (Desktop Menu Specification): Game, WebBrowser, then Player or Video for players; an audio program without Video (Elisa) is another program. A program sent from an NVIDIA desktop to a Mesa GPU also gets Mesa's EGL and GLX vendors (__EGL_VENDOR_LIBRARY_FILENAMES, __GLX_VENDOR_LIBRARY_NAME), since glvnd would try NVIDIA's first.
- The machine record: /etc/xdg/sparky-stereo-graphicsrc, groups [Measured] (BestGpu, Model, Measurement) and [Decoding] (CopyBack), beneath the person's own ~/.config/sparky-stereo-graphicsrc. libmedia-gpu-route reads [Decoding] CopyBack from the same two files. sparky-stereo-gpu-record writes it: at boot (sparky-stereo-gpu-record.service) from the record shipped for a known model in /usr/share/sparky-stereo-graphics/machines, matched by the firmware's make and model and exactly the machine's display controllers; or from a measurement or an administrator on the machine (--set-best, --copy-back), which the boot service never replaces. A shipped record for another model is removed at boot, so a disk moved to another computer does not carry it. Shipped: the Lenovo ideapad 310-15ABR (A10-9600P), where 3D film dropped 589.6 frames a minute on the integrated R5 that drives the screens and 65.3 on the R5 M430, and copying decoded pictures back dropped more than software decoding (ORDER 234).
- Video decoding: "Copy decoded video back", the [Decoding] CopyBack key of the person's file. Off unless the person or the machine's record turns it on; a player's own decoder choice always wins, and MEDIA_GPU_ROUTE_COPY_BACK set in the session wins and the page says so.
- Programs: one list of menu entries, each "same as its group", "the dedicated GPU" or "the main GPU". The dedicated GPU means what KDE's launcher does with the key: the first discrete GPU, or no change when the GPU the computer starts with (its boot VGA) is already discrete. It is KDE's own PrefersNonDefaultGPU key in the person's copy of the entry (the same setting as Run Using Dedicated Graphics, written the way KMenuEdit writes it); there is no second list. A copy the page made follows the system entry when a package updates it, until the person edits it; an unchanged copy is deleted when the setting goes back to "same as its group".
- GPU power: power-profiles-daemon's GPU actions (amdgpu_dpm, amdgpu_panel_power) as switches; they are shown with one GPU as well.
Nothing is written until Apply. Defaults clears the main GPU, the render choices and the copy-back choice; a value equal to the machine's record is not written, so a better record later reaches everyone who never chose.

Commands
-------------
sparky-stereo-gpu-env: what the page decides, for programs that start programs (--category, --app ID or the path of a desktop file, --choice, --3d, --profile, --print, --shell, --session, --list, --json). Plasma's launcher (KIO, kf6-kio 6.30.0-1+stereo3d6) asks it with --app for every program whose desktop entry does not set PrefersNonDefaultGPU; libmedia-gpu-route asks it which GPU players decode on.
sparky-stereo-gpu-run [--category C | --app ID] [--3d] COMMAND: starts a program on its GPU; in Steam, set a game's launch options to `sparky-stereo-gpu-run --category games %command%` (add --3d for a program presenting 3D). A GPU already chosen in its environment (DRI_PRIME, MESA_VK_DEVICE_SELECT, VK_LOADER_DRIVERS_SELECT, __NV_PRIME_RENDER_OFFLOAD) is kept. It never stops a program from starting.
sparky-stereo-gpu-record (root): --apply-known, --set-best GPU [--copy-back true|false] [--model TEXT] [--measurement TEXT], --copy-back true|false|unset, --forget, --show; --root DIR for another system's root.

Tests
-------------
autotests: the machine record (system folders, matching a known model, the boot service's rules, what the tool writes), GPU listing from sysfs fixtures (one GPU, the A10's two AMD, the workstation's AMD and NVIDIA, a BMC board, three GPUs), saved choices, the power-profile mapping, the application list through KDE's own KService, the command line and the session script (with the edition's own primary-gpu script after it), the page and its QML on four machines, the power switches against a stand-in power-profiles-daemon on a private bus, and the translations of the nine languages.
