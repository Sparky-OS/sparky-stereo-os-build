# Measuring the Rust compiler on this laptop

This folder compares the same Rust 1.99.1 toolchain built from authored sources, Lean Code's ordinary-comment projection, and an experimental form that also removes documentation comments where the build permits it.

Start from a copy on the laptop's root filesystem, with at least 80 GiB free. Run `./run.sh`. Read progress with `./status.sh`; detailed logs are in `runtime/worker.log`, and accepted results are under `results/`. The worker keeps running after the terminal closes. After a reboot by you, run `./run.sh` again. Finished steps are verified and skipped. A step interrupted before its receipt is written starts afresh, with an empty build tree.

`./pause.sh` requests a pause after the current whole step, which can take hours. `./run.sh` resumes it. For an immediate stop, send TERM to the worker PID shown by `./status.sh`; that unfinished step will be discarded on resume. Do not remove the folder while it is running.

The experiment uses all four CPU cores, up to 8 GiB of memory, and substantial disk space. The laptop will get hot, and the desktop may respond more slowly. Keep it plugged in, ventilated, and on a firm surface. The kit never changes display modes, KWin, the desktop session, power settings, swap, or the machine's boot state.

Each container waits for CPU temperature at or below 62 °C. Above 90 °C it pauses, and resumes at or below 62 °C. A two-hour failure to cool stops with a reason. Temperature, frequency, governor, load and kernel accompany the results. Disk space is sampled every five seconds, including during extraction and image loading; work stops five GiB above the configured floor. An unfinished step contributes no result.

The folder carries its sources, dependencies, offline workload and pinned container image. It uses passwordless `sudo -n podman` for an isolated container store inside `runtime/`. This permits the contained perf counter capabilities. It installs the experimental compilers only inside throwaway containers, never as the laptop's compiler. Every build and runtime container uses `--network none --pull=never`. Nothing is downloaded during measurement. Missing tools, denied counters, an unexpected compiler, missing sensors, or checksum failures stop explicitly.

When complete, read `summary/REPORT.md` and `summary/summary.json`. Timing differences include all observed spread, and single whole builds do not establish a repeatable whole-build speed difference. `results/analyze/result/` contains package-file and ELF-section differences, program-byte comparisons and the standard-library panic's authored location. Some differing code/constants/metadata bytes may remain unattributed; these are recorded as residual work, not explained by assumption.

The final plan and the preparation report give the estimated running time and its uncertainty. These estimates are not A10 measurements. Do not launch a preparation folder whose report still says `STATUS: working` or `STATUS: blocked`.
