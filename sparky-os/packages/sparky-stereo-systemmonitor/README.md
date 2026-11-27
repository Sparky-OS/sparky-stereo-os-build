sparky-stereo-systemmonitor
System Monitor's Overview fitted to the computer it runs on.

Copyright (C) 2026 Daniel Ramos (Capitain Jack), see copyright file.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

Dependencies:
-------------
python3
libkf6config-bin
sparky-stereo-problems

What it does:
-------------
Daniel, 2026-10-17: "system monitor overview presets for different configs like multiple GPUs and CPUs - current default is too narrow for both test targets (this and a10)"; "auto apply by hardware probe".
KDE's Overview shows one pie for every processor thread together and one for every graphics card together.

At a person's login, `/usr/libexec/sparky-stereo-systemmonitor/overview-pages --login` (the autostart entry `sparky-stereo-systemmonitor-pages.desktop`, only where System Monitor is installed) reads what System Monitor's sensor service, ksystemstats 6.7.4, reads:
- the graphics cards, in ksystemstats' order and numbering (gpu0, gpu1 ...: the PCI devices of class 0x030000, 0x030200 and 0x038000 of AMD, NVIDIA and Intel, in sysfs order);
- for each card, whether its driver reports usage, video memory, temperature and power: AMD from `gpu_busy_percent`, `mem_info_vram_used` and `mem_info_vram_total`, and the `amdgpu` hwmon chip's `temp1` and `power1` (`power1_input` or `power1_average`); NVIDIA from `nvidia-smi dmon -s pucm`, where a column printed as `-` is not reported (ksystemstats reads it as 0); Intel usage only, from the i915 PMU through `ksystemstats_intel_helper`, which needs its CAP_PERFMON or `perf_event_paranoid` at 0 or below;
- the processor threads, from `/proc/cpuinfo`.

It writes four presets into the person's System Monitor folder (`~/.local/share/plasma-systemmonitor`):

| Preset | For |
|---|---|
| Overview: one GPU, few threads | one card (or the card that draws the desktop), up to 8 threads: one chart with a line per thread |
| Overview: one GPU, many threads | one card, more than 8 threads: a grid of one chart per thread |
| Overview: every GPU, few threads | every card, side by side, four to a row |
| Overview: every GPU, many threads | every card, and the grid of threads |

Every preset keeps KDE's Memory, Swap, Disks, Networks and Applications.
Each card shows its usage chart, its name, video memory, temperature and power, each where its driver reports it.
A sensor the driver does not report is named on the card ("Not reported to System Monitor: usage, power") and is not on the page, so no zero stands for it.
A display device ksystemstats does not measure (another vendor's, a virtual machine's) is named on the "every GPU" presets.

The first time, the preset of the computer's class becomes the page System Monitor opens with (Ctrl+Alt+Del opens it), and KDE's Overview and the other three presets are listed in Edit Pages (right click on the sidebar, Edit or Remove Pages), hidden: KDE's Overview is one tick away.
A person who had already chosen (a start page, an order or hidden pages in `systemmonitorrc`, theirs or the administrator's in `/etc/xdg`), or who edited KDE's Overview, keeps their arrangement; the presets are only added, the three that do not fit hidden.
The choice is written once: what the person chooses afterwards is theirs and is never written again.
The presets are the person's pages: they edit them in System Monitor, and remove them in Edit Pages.

At the next logins nothing is read but the list of cards and threads.
When it changes, the presets the person did not edit are written again for the computer (a recorded digest tells them apart), a removed preset stays removed, and the person's choice stays.

When the computer cannot be read (no PCI devices in sysfs, no processor in `/proc/cpuinfo`), nothing is written, so KDE's Overview stays, and the person is told why through the edition's problems engine (key `overview-probe`, LOCAL2); Repair runs the probe again, and a later probe that works clears it.

`overview-pages --explain` prints what it read and the preset this computer gets, and writes nothing.
`overview-pages --compose one|every few|many FILE` writes one preset for this computer to FILE.

Tests:
-------------
`tests/run.sh` in a Debian testing container with python3, libkf6config-bin, ksystemstats and sparky-stereo-problems: the ten catalogues (`tests/catalogs.py`), then `tests/compose.py` on fixture computers (`tests/machines.py`: the two test targets as read on 2026-11-27, and synthetic computers with real IDs: Intel with and without perf, Intel on xe, an Intel and NVIDIA laptop whose NVIDIA reports no power, nouveau, NVIDIA without nvidia-smi, a virtual machine, a server with a BMC, five AMD cards, a computer with no PCI devices) and the login flow.

Credits:
-------------
KDE's System Monitor (plasma-systemmonitor) and ksystemstats, by Arjen Hiemstra, David Redondo and the KDE contributors; the GPU names of ksystemstats by Bernhard Friedreich; the words KDE already translated are KDE's translators' own.
