sparky-stereo-vram-boost
Decide at every boot whether the window in front gets VRAM protection.

Copyright (C) 2026 Daniel Ramos (Capitain Jack), see copyright file.

This program is free software: you can redistribute it and/or modify it
under the GNU General Public License, version 3 or any later version.

Dependencies:
-------------
bash
dmemcg-booster
systemd
plasma-foreground-booster (recommended)

Build:
-------------
OUT=/path/in/workspace/pending-pack bash ./build.sh

Install:
-------------
su
OUT=/path/to/packages bash ./install.sh

Uninstall:
-------------
su
bash ./install.sh uninstall

Use:
-------------
Nothing to run. At every boot sparky-stereo-vram-boost.service looks at the
kernel and the GPUs and writes its decision to /run/sparky-stereo-vram-boost:
the file enabled when dmemcg-booster (system and session) and
plasma-foreground-booster run, and state with the reason.
Their units carry ConditionPathExists=/run/sparky-stereo-vram-boost/enabled.

The default, auto, is on when the kernel has the dmem cgroup controller
(CONFIG_CGROUP_DMEM, Sparky Stereo kernels from build 13) and an AMD GPU
with its own VRAM has registered it with the controller: the case
Natalie Vock measured (pixelcluster.dev/VRAM-Mgmt-fixed). The other GPUs
whose drivers register VRAM (AMD APUs, Intel xe, nouveau) stay as they are
unless SPARKY_STEREO_VRAM_BOOST=yes is set in
/etc/default/sparky-stereo-vram-boost; no turns it off everywhere.
NVIDIA's own driver and machines without such a GPU never start it.
Each person can also turn the foreground booster off for their own session
with upstream's switch: autostart=false in the [Foreground Booster] group
of ~/.config/kcgroupsrc.
