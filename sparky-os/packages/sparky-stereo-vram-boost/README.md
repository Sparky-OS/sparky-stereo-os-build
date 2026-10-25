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
(CONFIG_CGROUP_DMEM, Sparky Stereo kernels from build 13) and any GPU has
registered its VRAM with it, including AMD cards and APUs, Intel xe and nouveau.
Set SPARKY_STEREO_VRAM_BOOST in /etc/default/sparky-stereo-vram-boost:
auto uses that default; amd-dgpu keeps the old rule, on only for an amdgpu
GPU with its own VRAM (mem_info_vram_vendor present) registered with dmem;
yes is the same as auto, kept for existing configurations; no turns it off.
With no registered VRAM it stays off, including NVIDIA's own driver,
which registers none.
Each person can also turn the foreground booster off for their own session
with upstream's switch: autostart=false in the [Foreground Booster] group
of ~/.config/kcgroupsrc.
