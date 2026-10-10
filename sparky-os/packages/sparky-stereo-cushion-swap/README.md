sparky-stereo-cushion-swap
The Cushion Swap File: the swap area stays off and is switched on only under memory pressure.

Copyright (C) 2026 Daniel Ramos (Capitain Jack), see copyright file.

This program is free software: you can redistribute it and/or modify it
under the GNU General Public License, version 3 or any later version.

Dependencies:
-------------
bash
libc6
systemd
util-linux

Build:
-------------
OUT=/path/in/workspace/pending-pack bash ./build.sh (inside a Debian container with gcc)

Install:
-------------
su
OUT=/path/to/packages bash ./install.sh

Uninstall:
-------------
su
bash ./install.sh uninstall

Daniel's design
-------------
The Cushion Swap File is Daniel Ramos's "Dynamic Swap Parachute", which he
asked for on 2026-08-01 and has run on his own workstation (96 GB of RAM, a
100 GiB swap file) since then. His doctrine line: "swap is a rescue
parachute, never a floor". On 2026-10-10 he made it the edition's swap:
"swapp off on boot ... swapp is on in the sense is available, otherwise
hibernation options won't even enable ... and the retraction is kept",
and named it the Cushion Swap File.

His rules, kept as he wrote them (usr/sbin/cushion-swap, run_cycle):
- Deploy when MemAvailable is below 6 GiB, or below 12 GiB and falling at
  least 1 GiB per 10 seconds (the rate gives the lead time a fast allocation
  would otherwise take away).
- Retract only when something is in swap, MemAvailable exceeds the swap in
  use plus 20 GiB (swapoff reads every swapped page back into RAM, so it must
  not cause the next emergency), and no deploy condition has been true for
  10 minutes.
- Fail safe: an unreadable /proc/meminfo or /proc/swaps means no action.
- OOMScoreAdjust=-1000, restarted if it dies, never sandboxed (swapon in a
  private mount namespace would do nothing to the real system).
His test harness (tests/test_swap_parachute.sh, 12 scenarios, 39 assertions)
runs unchanged against this daemon; only its daemon path, scratch folder and
the fixture area name differ.

What the edition adds around his rules
-------------
- The area. Only one swap area is ever switched: AREA= in
  /etc/default/cushion-swap, or the first swap line in /etc/fstab marked
  noauto (the installer writes it so; swapon -a skips noauto lines, so the
  area stays off at boot). zram and every other swap area are left alone.
  His host version ran "swapon -a && mount -a"; the edition runs
  "swapon AREA" and "swapoff AREA" only, and no mount -a.
- Thresholds for every machine. At or above 90 GiB of MemTotal, his values
  apply exactly as written (his machine reports 93.42 GiB; every 96 GB
  machine reports 92 to 95 GiB). Below that, each memory value is the same
  share of RAM as on his machine:
  value = his value x MemTotal / 90 GiB, with a floor of 256 MiB (hard),
  512 MiB (soft and margin) and 16 MiB per 10 s (rate). The time values (rate
  window 10 s, quiet window 10 min) do not change. Why scale: a 6 GiB floor
  on a 16 GB machine would switch the swap on while 40 % of RAM is still
  available, which is the "floor" his doctrine rules out.

  | RAM | MemTotal (fixture) | deploy below | early warning below | falling faster than | retract margin |
  | --- | --- | --- | --- | --- | --- |
  | 4 GB | 3.88 GiB | 265 MiB | 530 MiB | 44 MiB / 10 s | 884 MiB |
  | 8 GB | 7.78 GiB | 531 MiB | 1.04 GiB | 89 MiB / 10 s | 1.73 GiB |
  | 16 GB | 15.57 GiB | 1.04 GiB | 2.08 GiB | 177 MiB / 10 s | 3.46 GiB |
  | 32 GB | 31.14 GiB | 2.08 GiB | 4.15 GiB | 354 MiB / 10 s | 6.92 GiB |
  | 64 GB | 62.28 GiB | 4.15 GiB | 8.30 GiB | 709 MiB / 10 s | 13.84 GiB |
  | 96 GB | 93.42 GiB | 6 GiB | 12 GiB | 1 GiB / 10 s | 20 GiB |

  Every value can be set in /etc/default/cushion-swap (DEPLOY_HARD_MIB,
  DEPLOY_SOFT_MIB, RATE_MIB, RETRACT_MARGIN_MIB; his GiB names
  DEPLOY_HARD_GIB and the others are accepted too), and
  "cushion-swap --thresholds" prints what this machine uses and why.
- The wake-up, as Daniel settled it (PACING=fixed, the default). Where the
  kernel has pressure stall information (PSI), /usr/libexec/cushion-swap/psi-wake
  holds a trigger on /proc/pressure/memory ("some 150000 1000000": 150 ms of
  stall in one second, the example of the kernel's
  Documentation/accounting/psi.rst) and the kernel wakes the daemon when
  memory stalls; his rules still make every decision. A 10-second safety
  tick (his rate window) keeps the retract timer and slow drifts covered.
  Without PSI (older kernels, psi=0, containers: Docker's AppArmor profile
  refuses the trigger), his 3-second poller runs, at 0.5 seconds only while a
  game is opening: sparky-stereo-game-performance touches
  $XDG_RUNTIME_DIR/cushion-swap-game-opening, and a new launcher process
  (Steam's reaper and launch wrapper, pressure-vessel, umu, Proton, Wine,
  Lutris, gamemoderun, Legendary, gogdl) counts too; only processes started
  since the last look are read. The fast rate ends when available memory has
  moved less than his rate threshold for 10 seconds, or after 3 minutes.
- The proposed pacing (PACING=headroom, not the default; Daniel decides):
  the next sample comes before memory could fall to the early-warning floor
  at 8 GiB/s (MAX_ALLOC_MIB_S), never sooner than 0.25 s and never later than
  the normal interval; PSI still wakes it at once. Far from the floor it
  samples as rarely as the settled design; near it, often. Measured below.
- Hibernation with the area off at boot (below).
- Logging: an action, a failure or a deploy/retract condition is logged with
  its arithmetic; LOG_EVERY_CYCLE=yes logs every cycle as his host version
  does.
- CUSHION_SWAP=off in /etc/default/cushion-swap stops it; like his
  uninstall.sh, stopping never switches the swap off ("removing the watcher
  is not the same decision as forcing swap off").
- Where his own /etc/systemd/system/cgm-swap-parachute.service exists, the
  packaged units do not start.

Hibernate with the swap off
-------------
KDE offers Hibernate when logind's CanHibernate answers yes
(plasma-workspace libkworkspace/sessionmanagementbackend.cpp). logind answers
yes only with an active swap area that can hold the image
(systemd src/shared/hibernate-util.c, hibernation_is_safe() and
find_suitable_hibernation_device_full(): "No swap space available for
hibernation"), unless SYSTEMD_BYPASS_HIBERNATION_MEMORY_CHECK=1 is set for
it (systemd docs/ENVIRONMENT.md). And systemd-sleep looks for the area before
it runs the system-sleep hooks (src/sleep/sleep.c), so a hook is too late.
So the package:
- cushion-swap-hibernate-generator sets that variable for systemd-logind
  only where hibernation can work: an area is configured, the kernel command
  line has resume=, and the area is at least the size of RAM when it can be
  checked at boot. HIBERNATE=off in /etc/default/cushion-swap turns it off.
- cushion-swap-hibernate.service, ordered before systemd-hibernate.service
  (and hybrid-sleep, suspend-then-hibernate), switches the area on.
- After resume, the system-sleep hook switches it off again if it was
  switched on only for the image and nothing stayed in it; pages that did
  stay are left to his retract rules.

Prior art
-------------
- swapspace (Debian package swapspace; Software Industry Promotion Agency of
  Thailand 2004-2006, Jeroen T. Vermeulen 2010-2012, Jacob Adams since 2014)
  creates and deletes swap files as the need grows and shrinks. Its README
  says that suspend and resume still need a static swap file.
- macOS (Apple's dynamic_pager) also adds swap files on demand.
- systemd-oomd (the systemd project) kills a cgroup when memory pressure
  stays high, instead of giving it swap.
- Daniel's design differs: the area is allocated in advance and stays off at
  rest, so it needs no disk-space decisions under pressure and can hold a
  hibernation image; it deploys ahead of the floor from the rate of descent;
  and it retracts only after a quiet window and when the arithmetic shows
  that swapoff cannot itself run the machine out of memory.

Measured (development VM, 16 GB, 4 vCPUs, 2026-10-10)
-------------
- Without swap, from 14 GiB available to the OOM kill (MemTotal 15.6 GiB:
  deploy below 1.04 GiB, early warning below 2.08 GiB): at 256 MiB/s the hard
  floor is crossed 4.6 s before the kill, at 1 GiB/s 1.1 s, at full speed
  (one allocating thread, about 4.8 GiB/s) 1.3 s. The PSI trigger first fired
  at 377 MiB available, after the kill, and at 66 MiB: memory stalls show up
  only at the very end, when swap is off and the page cache is gone.
- swapon of a 2 GiB swap file: 4 to 7 ms.
- The packaged daemon with a 2 GiB area, allocating 1 GiB beyond what is
  available at full speed, the start at a random moment (8 runs each):
  his 3 s poller completed 3, PSI with the 10 s tick 6, the proposed headroom
  pacing 8. (With the start always 13 s after the daemon, all 6 runs of each
  completed: the sampling phase decides it.)
- systemd-oomd (Debian's default: user@.service at 50 % pressure for 20 s):
  in four runs inside user@1000.service it never acted; the kernel's OOM
  killer or the Cushion Swap File always came first. The unit is ordered
  before systemd-oomd.service.
- CPU while idle (120 s): see ../../power-idle/evidence/cushion-swap/.

Status
-------------
/run/cushion-swap/status (read by the System Settings page and by
"cushion-swap --status"): STATE (off, deployed, retracting, disabled,
no-area), MODE (psi, compatibility), FAST, AREA and the thresholds in use.

Tests
-------------
tests/run-tests.sh runs in a container as an ordinary user: the thresholds
for 4, 8, 16, 32, 64 and 96 GB, settings, deploy and retract on the own area
only, fstab detection, the off switch, the hibernation units' commands, the
compatibility loop's game-opening rate, the PSI fallback, the generator and
Daniel's harness; then six planted faults (deploying too late, no rate
trigger, retracting under pressure, retracting without the margin, every swap
area, a stuck fast rate) must each fail their check. tests/run-tests.sh
--psi-pressure, in a container started with --memory, proves a real PSI
trigger fires under pressure and stays quiet without it. tests/guest/ holds
the guest-only race measurements (README in the edition's power-idle notes).
