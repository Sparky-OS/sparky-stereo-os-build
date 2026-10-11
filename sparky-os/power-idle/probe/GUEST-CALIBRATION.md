# Cushion Swap File 0.3.0 guest proofs

Run as root in the disposable headless development VM, not on a workstation.
Install 0.3.0 and let its first idle calibration finish. Stop the guest display
manager for the idle measurement; do not run a pressure test at the same time.
Each probe writes JSON to its first argument and returns nonzero on a mismatch.
The output directory must already exist. No extra Python packages are needed.

`guest-pacing.py OUT.json OLD_DAEMON --seconds 40` compares the accepted 0.2.0
daemon with the installed daemon. Retrieve OLD_DAEMON from the accepted Git
revision, not an edited replacement. Both runs use compatibility mode and
opt-in cycle logs. CPU is process user plus system time as a percentage of one
core. Weekly bytes project the measured file growth over 604800 seconds.
Run separately with 4 GiB and 16 GiB guest RAM. The production service is
stopped during measurement and restored afterwards; no swap is changed.

`guest-calibrated-race.py OUT.json` needs the package's `tests/guest/memgrow.py`
in the adjacent `guest/` directory. It uses the cached measured MiB/s as the
allocator's aggregate target rate across the same number of workers as the
benchmark, with huge pages disabled, and the cached safety rate as the daemon's assumed
rate. Actual allocation can slow under reclaim and swap I/O. Six deterministic
random-phase starts must all complete and deploy. Two starts assume only
1 MiB/s; at least one must lose to the OOM killer, matched by PID in dmesg. The allocation target is
MemAvailable plus 512 MiB, ensuring the control actually exceeds available RAM.
Only its own preallocated 2 GiB scratch disk swap is managed. Zram is temporarily
stopped and runtime-masked so it cannot conceal the negative control; other
active swap is a prerequisite failure. Zram and the production service are
restored; scratch swap is switched off before deletion. Requires swappiness 1.
Allow 2 GiB of guest disk growth above the host disk floors.

`guest-log.py OUT.json` temporarily opts into fixed-rate cycle logging through
/etc/default/cushion-swap and the actual production service. It checks file
ownership and growth, forces three rotations with a private logrotate state,
records any copytruncate boundary gaps, checks that an unforced repeat does not
rotate, and restores settings and the service. Forced rotations are test-only;
the shipped policy remains weekly. With rotate 1 and delaycompress, the only
archive is .1, uncompressed.

The 96 GiB log-volume case is a container RAM fixture, not a claim about
Daniel's workstation. Its available-memory value and assumed-rate override
must be recorded beside the projected bytes.

`guest-default-log.py OUT.json --seconds 20` checks the actual idle production
service after the other probes restore it. It checks that its log size stays
unchanged and that the daemon's PID writes nothing to the journal, and records
CPU and runtime state. A memory-pressure action during this window is a
mismatch; run it while idle with no pressure workload.
