sparky-stereo-kernel-settings
Kernel tunables for Sparky Stereo OS as user-space files: sysctl, udev, tmpfiles, modules-load and audio limits.
No zram (Daniel, 2026-10-10): it holds part of the user's RAM captive; the edition's swap is an emergency swap file, on only under memory pressure.

Copyright (C) 2026 Daniel Ramos (Capitain Jack), see copyright file.
Derived from CachyOS-Settings (GPL-3.0) and the CachyOS kernel patches, and from the value SteamOS uses for vm.max_map_count; authors in the copyright file.

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later version.

Dependencies:
-------------
libpam-modules
systemd
udev

Build:
-------------
OUT=/path/in/workspace/pending-pack ./build.sh (inside a container)

Install:
-------------
su
OUT=/path/to/packages ./install.sh

Uninstall:
-------------
su
./install.sh uninstall

What it sets (every value can be overridden in /etc/sysctl.d/ and /etc/udev/rules.d/):
usr/lib/sysctl.d/70-sparky-stereo.conf      15 keys, each with its reason. The last one, kernel.kexec_load_disabled = 1,
                                            closes kexec_load and kexec_file_load until the next boot (Daniel's decision,
                                            2026-10-08). The kernel's own default is 0: this file is the only place the
                                            edition sets it. Delete that line to keep kexec and kdump usable.
usr/lib/modules-load.d/sparky-stereo.conf   loads ntsync (Wine/Proton)
usr/lib/udev/rules.d/70-sparky-ntsync.rules /dev/ntsync for the logged-in user
usr/lib/udev/rules.d/60-sparky-block.rules  BFQ on rotating disks, 256 KiB read-ahead
usr/lib/udev/rules.d/99-sparky-audio.rules  audio group: cpu_dma_latency, rtc0, hpet
usr/lib/tmpfiles.d/sparky-thp.conf          THP defrag defer+madvise, THP shrinker threshold
etc/security/limits.d/20-sparky-audio.conf  rtprio 99 and nice -11 for @audio (a conffile)

No maintainer scripts: the settings apply at the next boot (or: sysctl --system, systemd-tmpfiles --create, udevadm control --reload).
Not taken from CachyOS, on purpose: SATA link power max_performance (costs laptop battery), journald and systemd timeouts (distribution policy),
kernel.printk and kernel.sysrq (Debian's defaults stay), the NVMe kyber scheduler (no measurement favours it), the HDA power-save script.
