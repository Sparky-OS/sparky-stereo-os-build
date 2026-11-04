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
sparky-stereo-problems >= 0.1.2
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

Protection is off by default, with no boot wait in any mode.
In System Settings, Graphics, switch on "Protect the video memory of the program in front" to opt in.
Background programs give up video memory first, and the program in front gets a higher CPU priority.
The setting is SPARKY_STEREO_VRAM_BOOST in /etc/default/sparky-stereo-vram-boost.
Use yes for every GPU with a registered dmem region, amd-dgpu for an amdgpu GPU with its own VRAM
(mem_info_vram_vendor present), or no to turn it off.
The retired auto value means off; it cannot turn a former default into the person's opt-in.
Changes take effect after a restart.
The boot run reads the regions already registered; it never sleeps or polls for a driver.
NVIDIA 615.71.09 was measured registering nvidia/00000000:01:00.0/vidmem on the station.
No claim is made about the first NVIDIA version to support this.
An explicit opt-in that cannot work is kept by sparky-stereo-problems and shown in the session and on the Graphics page:
a kernel without dmem, an unreadable capacity, or a GPU with no matching region.
An invalid mode is also kept; no and auto keep no problem and clear earlier ones.
The next successful boot run clears the repaired problem.
Each person can also turn the foreground booster off for their own session
with upstream's switch: autostart=false in the [Foreground Booster] group
of ~/.config/kcgroupsrc.
