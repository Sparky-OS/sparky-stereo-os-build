sparky-stereo-cushion-swap
The Cushion Swap File: the swap area stays off and is switched on only under memory pressure.

Copyright (C) 2026 Daniel Ramos (Capitain Jack), see copyright file.

This program is free software: you can redistribute it and/or modify it
under the GNU General Public License, version 3 or any later version.

Dependencies:
-------------
bash
libc6
logrotate
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
and named it the Cushion Swap File. The same evening he decided the nine
proposals of version 0.1.0 ("agreed on proposals"); version 0.2.0 carries
them out. Version 0.3.0 follows his 22:47 answers: idle calibration,
problems-only logging and enforced weekly rotation.

His rules, kept as he wrote them (usr/sbin/cushion-swap, run_cycle):
- Deploy when MemAvailable is below 6 GiB, or below 12 GiB and falling at
  least 1 GiB per 10 seconds (the rate gives the lead time a fast allocation
  would otherwise take away).
- Retract only when something is in swap, MemAvailable exceeds the swap in
  use plus 20 GiB (swapoff reads every swapped page back into RAM, so it must
  not cause the next emergency), and no deploy condition has been true for
  10 minutes.
- Fail safe: an unreadable /proc/meminfo or /proc/swaps means no action.
- Version 0.3.0 logs failures and DEPLOY/RETRACT arithmetic by default.
  LOG_EVERY_CYCLE=yes enables his original cycle arithmetic.
- OOMScoreAdjust=-1000, restarted if it dies, never sandboxed (swapon in a
  private mount namespace would do nothing to the real system).
His test harness (tests/test_swap_parachute.sh, 12 scenarios, 39 assertions)
runs unchanged against this daemon; only its daemon path, scratch folder and
the fixture area name differ.

What the edition adds around his rules
-------------
- The area. Only one swap area is ever switched by the daemon: AREA= in
  /etc/default/cushion-swap, or the first swap line in /etc/fstab marked
  noauto (the installer writes it so; swapon -a skips noauto lines, so the
  area stays off at boot). zram and every other swap area are left alone.
  His host version ran "swapon -a && mount -a"; the edition runs
  "swapon AREA" and "swapoff AREA" only, and no mount -a.
- An area that holds nothing (Daniel, 2026-10-10: "switch it off after the
  quiet window only if you make hibernation ignore this and keep enabled").
  An area that is on and was never used, or holds nothing any more, is
  switched off once no deploy condition has been true for the quiet window;
  swapoff then reads nothing back, so his margin has nothing to protect.
  Hibernate stays offered and working with the area off (below). While a
  hibernation is using the area (the hibernate unit switched it on and the
  sleep hook has not yet run after resume), nothing is retracted: the hold
  ends with the sleep hook, or after HIBERNATE_HOLD_SEC (300 s) for a
  hibernation that never started (systemd-sleep runs no hook when it cannot
  find its area).
- Thresholds for every machine (decided 2026-10-10). At or above 90 GiB of
  MemTotal, his values apply exactly as written (his machine reports
  93.42 GiB; every 96 GB machine reports 92 to 95 GiB). Below that, each
  memory value is the same share of RAM as on his machine:
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
- The wake-up, as Daniel settled it. Where the kernel has pressure stall
  information (PSI), /usr/libexec/cushion-swap/psi-wake holds a trigger on
  /proc/pressure/memory ("some 150000 1000000": 150 ms of stall in one
  second, the example of the kernel's Documentation/accounting/psi.rst) and
  the kernel wakes the daemon when memory stalls; his rules still make every
  decision. A 10-second safety tick (his rate window) keeps the retract timer
  and slow drifts covered. Without PSI (older kernels, psi=0, containers:
  Docker's AppArmor profile refuses the trigger), his 3-second poller runs,
  and 0.5 seconds while a game is opening: sparky-stereo-game-performance
  touches $XDG_RUNTIME_DIR/cushion-swap-game-opening, and a new launcher
  process (Steam's reaper and launch wrapper, pressure-vessel, umu, Proton,
  Wine, Lutris, gamemoderun, Legendary, gogdl) counts too; only processes
  started since the last look are read. The fast rate ends when available
  memory has moved less than his rate threshold for 10 seconds, or after
  3 minutes.
- Pacing (PACING=headroom). At the first idle opportunity, the native
  alloc-rate helper measures fresh base-page faults: up to four workers,
  16 MiB each, up to three rounds. Memory is released each round; data peaks
  at 64 MiB plus thread stacks. It stops taking further rounds after 0.2 s;
  a slow first round can take longer. Calibration waits for two CPU samples
  ten seconds apart with at least 90% idle CPU, no memory PSI stalls, no
  game-opening signal or running known launcher, and available memory above the soft
  floor plus 256 MiB. It therefore waits through a game instead of measuring
  at startup regardless of load.
  /var/lib/cushion-swap/allocation-rate keeps the fastest measured rate,
  CPU count, workers and duration with the kernel/CPU/RAM fingerprint.
  Restarts reuse it; a changed kernel release, CPU identity, microcode,
  online CPU map or MemTotal invalidates it. Where firmware exposes DMI
  records, their opaque hash also catches equal-capacity RAM replacements.
  Hardware changes not exposed in these records require deleting the cache
  and restarting the service while idle.
  The assumed maximum is measured MiB/s x available CPUs / workers x 2.
  CPU scaling allows concurrent allocation on all CPUs; the 2x margin
  covers transient speedups beyond the short benchmark. Until idle
  calibration succeeds, the conservative 8192 MiB/s fallback applies.
  MAX_ALLOC_MIB_S in /etc/default/cushion-swap overrides calibration.
  The next sample uses (MemAvailable - soft floor) / assumed rate, capped
  by the normal 3 s, PSI safety tick 10 s or game-opening 0.5 s interval.
  The usual minimum of 0.25 s is shortened when half the hard-floor
  headroom would run out faster. PSI can still wake it earlier.
  PACING=fixed retains the original intervals.
- CUSHION_SWAP=off in /etc/default/cushion-swap stops it; like his
  uninstall.sh, stopping never switches the swap off ("removing the watcher
  is not the same decision as forcing swap off").
- Where his own /etc/systemd/system/cgm-swap-parachute.service exists, the
  packaged units and the generator do nothing.

The log
-------------
LOG_EVERY_CYCLE=no is the default. Startup failures, other failures, DEPLOY
and the RETRACT ending it carry their arithmetic to both
/var/log/cushion-swap/cushion-swap.log and the journal. Successful startup,
idle samples and routine decisions are quiet. Read problems with
"journalctl -u cushion-swap" or "tail -f /var/log/cushion-swap/cushion-swap.log".
The directory is root:adm 0750 and the file root:adm 0640.

Set LOG_EVERY_CYCLE=yes in /etc/default/cushion-swap and restart the service
when investigating a load. Sample, deploy-check and retract-check lines
then go to the file only; problem lines still go to both destinations.
Restore LOG_EVERY_CYCLE=no afterwards. The config file documents this.
Opt-in weekly volumes are measured below; these are projections from short
idle runs, not a week's collected logs, and change with available memory,
CPU speed, PSI/game signals and workload.

/etc/logrotate.d/sparky-stereo-cushion-swap uses weekly, rotate 1, compress,
delaycompress, missingok, notifempty, copytruncate. There is no maxsize,
hourly timer or earlier size trigger. Debian's daily logrotate invocation
checks whether a week elapsed. A forced run is used only by the probe.
With rotate 1 plus delaycompress the sole retained .1 stays uncompressed:
it is deleted at the next rotation before it could become .2.gz. This is
the specified policy. Disk budgeting must allow the current week and one
uncompressed previous week. copytruncate can lose writes between copying
and truncating (logrotate(8)); test measurements report that window's loss,
not a guarantee of lossless rotation. The unit appends after truncation.
No LogNamespace or mount namespace is introduced.

Hibernate with the swap off
-------------
Where the image goes is set by the installer in
/etc/initramfs-tools/conf.d/resume (Daniel, 2026-10-10: "pointing to the
file"):
- RESUME=UUID=... names the device: a swap partition (it does not need a line
  in /etc/fstab), or, for a swap file, the file system the file is on;
- RESUME_OFFSET= the swap file's first page on that file system;
- RESUME=none (or an empty RESUME=) means no hibernation.
The variables are Debian's initramfs-tools ones (initramfs.conf(5) for
RESUME; initramfs-tools(7) for the resume and resume_offset boot
parameters). Without a RESUME= line in that file, resume= and
resume_offset= on the kernel command line are the second source.
"cushion-swap --resume-target" prints which source decided, the area it
names and its size.

One gap in initramfs-tools 0.151 (Debian forky, read in its own scripts): it
reads RESUME from conf.d, but RESUME_OFFSET nowhere. Its init takes
resume_offset only from the kernel command line, or from a conf.d snippet,
which it sources before reading the command line. So a swap file set up in
the file alone would not resume. The package's initramfs hook
(/usr/share/initramfs-tools/hooks/cushion-swap-resume-offset) writes the
file's RESUME_OFFSET into the image as that snippet; a resume_offset= on the
command line still wins. The package triggers update-initramfs. initramfs-tools
warns "no matching swap device is available" for a swap file (it checks the
file system, which is not a swap device); that warning is expected.

KDE offers Hibernate when logind's CanHibernate answers yes
(plasma-workspace libkworkspace/sessionmanagementbackend.cpp). logind answers
yes only with an active swap area that can hold the image
(systemd src/shared/hibernate-util.c, hibernation_is_safe() and
find_suitable_hibernation_device_full(): "No swap space available for
hibernation"), unless SYSTEMD_BYPASS_HIBERNATION_MEMORY_CHECK=1 is set for
it (systemd docs/ENVIRONMENT.md). And systemd-sleep looks for the area before
it runs the system-sleep hooks (src/sleep/sleep.c); with a resume device set
by the initramfs, it accepts only the active swap that matches it. So the
package:
- cushion-swap-hibernate-generator sets that variable for systemd-logind
  where the file (or the command line) names a device, unless what can be
  checked at boot says otherwise: the area is smaller than RAM, or the swap
  files on that file system are all at other offsets. It logs which source
  decided. HIBERNATE=off in /etc/default/cushion-swap turns it off.
- cushion-swap-hibernate.service, ordered before systemd-hibernate.service
  (and hybrid-sleep, suspend-then-hibernate), switches that area on, whether
  or not it is the Cushion Swap File's area, and says in the journal when the
  kernel's resume device disagrees with the file.
- After resume, the system-sleep hook switches it off again if it was
  switched on only for the image and nothing stayed in it; pages that did
  stay are left to his retract rules.
- Retracting an unused area changes none of this: the generator does not look
  at whether the area is on.

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
- The packaged daemon (0.1.0) with a 2 GiB area, allocating 1 GiB beyond
  what is available at full speed, the start at a random moment (8 runs
  each): his 3 s poller completed 3, PSI with the 10 s tick 6, headroom
  pacing 8. (With the start always 13 s after the daemon, all 6 runs of each
  completed: the sampling phase decides it.) That result made headroom the
  default.
- systemd-oomd (Debian's default: user@.service at 50 % pressure for 20 s):
  in four runs inside user@1000.service it never acted; the kernel's OOM
  killer or the Cushion Swap File always came first. The unit is ordered
  before systemd-oomd.service.
- CPU while idle (120 s): see ../../power-idle/evidence/cushion-swap/.

0.3.0 measurements (2026-10-11)
-------------
Headless development VM, four vCPUs, guest display manager stopped. Each
before/after sample lasts 40 s, comparing accepted 0.2.0 to 0.3.0 with
compatibility mode and opt-in cycle logs. CPU is percent of one core.
The two 4 GiB samples are both retained: calibration and cost vary on this
shared host. The final faster calibration did not lower measured CPU.

| RAM case | measured / assumed MiB/s | interval before / after | CPU before / after | cycle log MB per week after |
| --- | --- | --- | --- | --- |
| 4 GiB VM, first idle sample | 2504 / 5008 | 0.336 / 0.548 s | 1.25 / 0.725% | 603 |
| 4 GiB VM, final build | 3879 / 7758 | 0.303 / 0.325 s | 2.95 / 4.00% | 1015 |
| 16 GiB VM, final build | 2048 / 4096 | 1.538 / about 3 s | 0.525 / 0.175% | 108 |
| 96 GiB container fixture | explicit assumed 5008 | 3 s after | 0.167% after | 108 |

The 96 GiB case has 60 GiB MemAvailable and a recorded rate override; it
measures the compatibility loop, not Daniel's machine or a 96 GiB VM.
Weekly bytes = bytes written / sample seconds x 604800. MB here means
1,000,000 bytes. Retaining the previous uncompressed week can approximately
double these file sizes. Low headroom can shorten intervals further and
increase volume; these are observed idle projections, not maximum sizes.
Default logging has no cycle-volume cost.

The final four-worker base-page race uses the cached 3879 MiB/s as the
aggregate allocator target and 7758 MiB/s for pacing. All six random-phase
runs completed and deployed the own 2 GiB disk swap. Both controls assuming
only 1 MiB/s lost a worker to the kernel OOM killer (PID checked in dmesg).
Allocation can slow under reclaim and disk I/O, so the JSON includes each
worker's actual reached-MiB/time output rather than claiming a sustained
rate throughout swapping. Zram was runtime-masked for this test and restored.
The 2x factor is a safety allowance, not a universal throughput guarantee.

Three forced copytruncate rotations lost zero cycles in the container and
one in the VM; unforced repeats did not rotate. The requested rotate 1 plus
delaycompress kept only the uncompressed .1. See the versioned JSON and
logs in ../../power-idle/evidence/cushion-swap/0.3.0/ and
../../power-idle/probe/GUEST-CALIBRATION.md for reproduction.

Status
-------------
/run/cushion-swap/status (read by the System Settings page and by
"cushion-swap --status"): STATE (off, deployed, retracting, disabled,
no-area), MODE (psi, compatibility), FAST, PACING, MAX_ALLOC_MIB_S, CALIBRATED, AREA and the thresholds in
use.

Tests
-------------
tests/run-tests.sh requires logrotate up front (exit 2 if absent) and runs
in a container as an ordinary user: the thresholds
for 4, 8, 16, 32, 64 and 96 GB, settings, deploy and retract on the own area
only, an unused area retracted after the quiet window and never during a
hibernation, fstab detection, the off switch, every cycle in the log file and
the actions in the journal too, the unit, tmpfiles and logrotate wiring, the
real logrotate rotating while the daemon writes, the generator's resume
sources (the file with a partition, the file with a swap file and its
offset, RESUME=none, the command line alone, neither, noresume, a wrong
offset, too small, switched off), Hibernate still offered after a retraction,
the hibernation units' switch-on and switch-off for a partition outside
fstab and for a swap file, the initramfs hook read back the way init reads
it, the compatibility loop's game-opening rate under both pacings, headroom
pacing, the PSI fallback and Daniel's harness. Then planted faults (deploying
too late, no rate trigger, retracting under pressure, without the margin, or
during a hibernation, every swap area, a stuck fast rate, fixed pacing by
default, headroom ignored or blind to a game, an unused area kept, Hibernate
offered only while the area is on, the switch-on skipped, actions missing
from the journal, routine logging by default, the logrotate file
absent or for another path, the unit logging elsewhere or in a log
namespace, the installer's file ignored, the hook dropping the offset) must
each fail their check. QUICK=1 skips the planted faults.
A real PSI trigger cannot be armed in a Docker container (its AppArmor
profile refuses the write to /proc/pressure/memory); tests/guest/psi-wake-check.sh
proves it in a VM: armed, quiet without pressure, firing under it.
(The 0.1.0 README named a "run-tests.sh --psi-pressure" mode that never
existed; corrected here.) tests/guest/ also holds the guest-only race
measurements (README in the edition's power-idle notes).

In Daniel's TV testing window (decided 2026-10-10): the launcher list and
the 0.5 s rate, measured on real game loads. Nothing here changes a game's
settings or the TV's mode.
1. Before: "cushion-swap --status" shows MODE. The game rate applies only
   in compatibility mode; on a kernel with PSI, start the daemon for this
   test with PSI=off in /etc/default/cushion-swap and restart it
   ("systemctl restart cushion-swap"); put the line back afterwards.
2. Temporarily set LOG_EVERY_CYCLE=yes and restart; restore it afterwards.
   Follow the log: "tail -f /var/log/cushion-swap/cushion-swap.log | grep -E
   'game opening|game loaded|longer than|sample:'".
3. Start each game the usual way: from Steam (native and Proton), from
   Lutris, from Heroic, and through game-performance. For each, note
   whether "game opening (signal from ...)" or "game opening (launcher
   process started)" appears within one cycle of the click, and the comm
   name of every process the launch starts ("ps -eo pid,comm,args
   --sort=start_time | tail -40" while it loads). A launcher whose processes
   are not in LAUNCHERS is a gap: write its comm name down.
4. During the load, the sample lines' timestamps show the rate: 0.5 s apart
   or less while the game loads, and back to the normal interval within
   10 s after its memory settles ("game loaded (memory steady for 10s)"), or
   after 3 minutes at most.
5. Record the lowest MemAvailable in the sample lines during each load, and
   whether a DEPLOY happened. The 0.5 s rate is right when no load fell from
   above the early-warning floor to below the hard floor between two
   samples; with a load that did, the next step is a faster rate or PSI.
6. Afterwards: "journalctl -u cushion-swap --since today" shows each action.
