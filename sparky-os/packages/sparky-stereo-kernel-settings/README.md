sparky-stereo-kernel-settings
Kernel tunables for Sparky Stereo OS as user-space files: sysctl, udev, tmpfiles, modules-load and audio limits.
zram by hardware (Daniel, 2026-10-10: "auto by hardware is the design"): off on capable machines, where it would hold part of the RAM captive; on only where it pays. The swap is the Cushion Swap File, on only under memory pressure.

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
usr/lib/systemd/zram-generator.conf.d/50-sparky-stereo.conf
                                            zram0 sized min(RAM, 8 GiB), lz4, priority 100, created only
                                            when usr/libexec/sparky-stereo/zram-auto prints 1
usr/libexec/sparky-stereo/zram-auto         the decision (see below); --explain prints it with the reason
etc/security/limits.d/20-sparky-audio.conf  rtprio 99 and nice -11 for @audio (a conffile)

No maintainer scripts: the settings apply at the next boot (or: sysctl --system, systemd-tmpfiles --create, udevadm control --reload).
Not taken from CachyOS, on purpose: SATA link power max_performance (costs laptop battery), journald and systemd timeouts (distribution policy),
kernel.printk and kernel.sysrq (Debian's defaults stay), the NVMe kyber scheduler (no measurement favours it), the HDA power-save script.

zram by hardware:
-------------
zram-generator runs zram-auto through its own set! directive and multiplies the zram size by what it prints (1 or 0); a
device of size 0 is not created, so a capable machine gets no zram unit at all. Its own host-memory-limit option can say
"not above this much RAM" but not "or when the swap area is on slow storage", hence the directive.
Automatic: on with 8 GB of RAM or less (MemTotal up to 9 GiB: 8 GB machines report 7.6 to 7.8 GiB, 12 GB machines 11.6),
or when the swap area (the Cushion Swap File's, else the root file system's disk) is eMMC, an SD card, a rotating disk
or removable storage; off on NVMe and SATA SSDs with more RAM. Through LUKS or LVM, the disks underneath decide.
Override: ZRAM=on, ZRAM=off or ZRAM=auto in /etc/default/sparky-stereo-zram (System Settings, Memory, writes it).
Sources: the kernel's Documentation/admin-guide/blockdev/zram.rst (compressed RAM block devices, swap among the uses);
Fedora's Changes/SwapOnZRAM (Fedora 33, owner Chris Murphy: zram for every machine at 50 % of RAM up to 4 GiB);
Android's memory management guide (developer.android.com/topic/performance/memory-management: zram instead of swap on
storage, because frequent writing wears that storage). The edition differs from Fedora: no zram where RAM is plenty.
Swappiness stays 1 with zram too (Daniel: "ram is fast, while it has it, leverage it"); zram is the last cushion before the
Cushion Swap File. lz4, not zstd: on the same real desktop memory zstd stored a third less but cost about twice the CPU
time to compress and to read back (measured, see the edition's power-idle evidence); the machines that get zram are the
ones with the least CPU to spare.

Your own sysctl values:
-------------
systemd-sysctl reads every *.conf in /etc/sysctl.d, /run/sysctl.d and /usr/lib/sysctl.d sorted by file name, whatever the
folder, and the last one wins (sysctl.d(5)). So a file of yours named 00-*.conf to 6*.conf loses to this package's
70-sparky-stereo.conf (measured: vm.swappiness = 10 in /etc/sysctl.d/00-mine.conf gives 1, in 99-mine.conf gives 10).
Put your value in a file that sorts after it (99-local.conf), or in /etc/sysctl.d/70-sparky-stereo.conf, which replaces
this package's file whole. Debian's procps 4.0.7 no longer ships /etc/sysctl.conf.
