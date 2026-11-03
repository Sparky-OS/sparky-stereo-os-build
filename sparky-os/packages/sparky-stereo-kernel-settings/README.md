sparky-stereo-kernel-settings
Kernel tunables for Sparky Stereo OS as user-space files: sysctl, udev, tmpfiles, modules-load and audio limits.
No compressed swap by default; the person may opt in through Stereo APTus. The swap is the Cushion Swap File on disk, on only under memory pressure.

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

/tmp on disk (Daniel: "the dumb /tmp mounted at a ram fs - final result? no ram"): the first install of 20261010.2
masks tmp.mount, the way Debian's trixie release notes describe it (5.1.6). This package never empties /tmp: Daniel
never asked for a wipe (2026-11-02), and 20261103.1 removes the boot-wipe rule earlier versions shipped. Debian's own
tmpfiles.d/tmp.conf still applies as Debian ships it. An administrator's own /etc/systemd/system/tmp.mount is left alone;
"systemctl unmask tmp.mount" brings /tmp in RAM back and is kept on upgrades. Purging the package removes the mask it
created. The change applies at the next boot.

Other settings apply at the next boot (or: sysctl --system, systemd-tmpfiles --create, udevadm control --reload).
Not taken from CachyOS, on purpose: SATA link power max_performance (costs laptop battery), journald and systemd timeouts (distribution policy),
kernel.printk and kernel.sysrq (Debian's defaults stay), the NVMe kyber scheduler (no measurement favours it), the HDA power-save script.

Compressed swap is the person's opt-in:
-------------
Nothing installs or configures zram by default, and there are no Conflicts, Breaks or Replaces against its packages.
The old edition generator drop-in identifies the migration; other swap areas are not retired.
Before unpack, an earlier ZRAM=on or a manually installed generator or zram-tools identifies a person's choice and prevents retirement.
The old configuration file is read for this migration, never written or removed.
A formerly auto-installed generator without that choice gets a persistent leftover marker.
The setup service guard blocks only that marker plus an auto-installed generator without ZRAM=on or a manually installed zram-tools.
No marker, a manually installed generator, ZRAM=on, or manually installed zram-tools passes.
The guard reads apt's extended_states; it never writes apt's state.
The generated swap unit runs after setup and checks the guard's runtime marker, so a skipped setup does not cause a futile swapon.
The generator may create an empty device node before the condition runs; no capacity or active swap is established by the blocked setup.
Installing the generator explicitly through apt or Stereo APTus marks it manual; the next setup passes without changing a mask or configuration.
Stereo APTus tells the person to restart for the generator's normal boot setup.
A kept notice explains the leftover and apt autoremove, in nine languages.
An earlier ZRAM=on with an automatic generator is protected using our own APT::NeverAutoRemove policy file, not by writing apt's database or running a second apt during configuration.
The person is told of this protection and can still explicitly uninstall the package.
An unsuccessful retirement is shown and kept in the problems engine with its repair command.

Your own sysctl values:
-------------
systemd-sysctl reads every *.conf in /etc/sysctl.d, /run/sysctl.d and /usr/lib/sysctl.d together, sorted by file name whatever the
folder, and the last value wins (sysctl.d(5)). The rule, also written at the top of 70-sparky-stereo.conf:
- name your own file 71-*.conf to 99-*.conf in /etc/sysctl.d (for example 99-mine.conf): its values win over this package's;
- or put a file named 70-sparky-stereo.conf in /etc/sysctl.d: it replaces this package's file completely.
A file numbered 00 to 69 loses to this package (measured: vm.swappiness = 10 in /etc/sysctl.d/00-mine.conf gives 1, in 99-mine.conf
gives 10). The package's file is 70, not lower, because 50-default.conf (package linux-sysctl-defaults, priority important: systemd's
upstream defaults) sets vm.max_map_count = 1048576, and the edition's value must come after it.
tests/sysctl-order-test.sh checks the rule with systemd's own file ordering (systemd-analyze cat-config sysctl.d).
Debian's procps 4.0.7 no longer ships /etc/sysctl.conf.

Swappiness:
-------------
Daniel's value is unchanged: "vm.swappiness = 1 always" (2026-10-10).
Our explanation follows Linux Documentation/admin-guide/sysctl/vm.rst, swappiness:
https://docs.kernel.org/admin-guide/sysctl/vm.html#swappiness
The range is 0 to 200 and expresses the relative I/O cost of swapping and filesystem paging.
A low value treats swap I/O as more expensive; 1 is not the minimum or a promise to retain every page in RAM.
At 0, swapping waits until free plus file-backed pages fall below a zone's high watermark.

Block-device read-ahead sources (checked 2026-11-02):
-------------
Daniel's rule is to follow the main gaming distributions (2026-11-02); this is disk read-ahead, not swap read-ahead.
The existing 256 KiB rule matches CachyOS/linux tag cachyos-7.3.1-1, include/linux/pagemap.h:1429, VM_READAHEAD_PAGES = SZ_256K / PAGE_SIZE.
That value initializes the backing device's ra_pages at mm/backing-dev.c:1037.
https://github.com/CachyOS/linux/blob/cachyos-7.3.1-1/include/linux/pagemap.h#L1429
Bazzite's Containerfile at 3a46cd99bc7aff9ffc962ec0fb595c2087484d8f:36-40 selects its OGC kernel through the akmods image.
OGC v7.0.9-ogc3 (dcad54d2480699ac5515a7372a106224d9106acc), matching that file's default kernel version, has SZ_128K at include/linux/pagemap.h:1368.
The newer OGC v7.3.1-ogc5 (e80cc3e80d31ad5d449d26d84e4a59946173090e) also has SZ_128K, at include/linux/pagemap.h:1429, applied at mm/backing-dev.c:1037.
https://github.com/OpenGamingCollective/linux/blob/e80cc3e80d31ad5d449d26d84e4a59946173090e/include/linux/pagemap.h#L1429
Thus their kernel defaults differ: CachyOS 256 KiB and Bazzite's OGC 128 KiB.
Bazzite additionally inherits tuned profiles, including throughput-performance, so its effective value can depend on the selected profile.
Our value follows CachyOS and remains 256 KiB; no swap setting is inferred from either distribution.
