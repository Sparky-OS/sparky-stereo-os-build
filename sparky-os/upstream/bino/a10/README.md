# Bino A10 published/candidate kit

This kit compares published `2.8-1+stereo3d2+lc1` with candidate `2.8-1+stereo3d3+lc1`.
Run it as the A10's desktop user in the existing Wayland session, during the main session's authorized TV testing window.
It selects these three setups, in order: TV-only 1080p30 frame packing on HDMI-A-1; both displays active with playback on HDMI-A-1; both displays active with playback on eDP-1.
The extended cases use the reviewed 1366x768@60 anaglyph panel mode and the same TV frame-packing mode.
Mode IDs are discovered from KScreen's mode attributes, not copied from an older boot.
The runner refuses hardware other than the reviewed Carrizo/Hainan A10.

## Install privately and run

The installer extracts both authenticated package payloads under this kit's `private/` directory.
It checks the published runtime versions and private Qt Multimedia ABI, then checks library resolution and startup.
It does not run apt, dpkg installation, maintainer scripts, sudo, or modify the installed Bino.
The runtime needs KWin +stereo3d34 or newer, libstereo-declare 1.6.0 or newer, Qt Multimedia 6.11.2 +stereo3d9 with its matching private ABI, the published Mesa stack, and Qt's SVG icon plugin.
The required KDE command-line tools must already be installed.
If these checks fail, update the published stack separately before running the kit.

```
./install-private.sh
./run-a10.sh --film /path/to/film.mkv \
  --kwin-log-dir /PATH/TO/THE/RUNNING/KWIN/CSV/DIRECTORY \
  --results "$HOME/bino-242-results-$(date +%Y%m%d-%H%M%S)"
```

Keep `WAYLAND_DISPLAY`, `XDG_SESSION_TYPE=wayland` and `DBUS_SESSION_BUS_ADDRESS` from the actual session.
The CSV directory is mandatory: KWin must already be running with `KWIN_LOG_PERFORMANCE_DATA=1` and writing `kwin perf statistics HDMI-A-1.csv` and, when enabled, `kwin perf statistics eDP-1.csv` there.
The kit checks that the files advance on the same monotonic clock as the case marks.
It never restarts KWin or changes its service environment.
If logging needs enabling after the reboot, the main session sets it up before the run.
Do not use `/tmp` for the results.

The default render choice is `DRI_PRIME=1`, the Hainan measured best on this A10.
An explicit `DRI_PRIME` environment value takes precedence; the same value is used for both executables and recorded with their OpenGL renderer logs.
Other explicit GPU environment choices are preserved and recorded.
Both executables use Wayland, the same clip, the same loop/input options and the same observer.
Published Bino receives `-o left-right`, as in `players-compare.py`; the candidate omits it because the edition build delegates output formats to KWin.
Per-case Bino preferences live under the results directory, so the user's Bino settings stay intact.

Defaults are a 40-second setup settle, 8 seconds before placing each window, 60 seconds of playback warmup and a 180-second measurement.
The runner verifies fullscreen placement using the observer's actual Qt window/screen state.
KWin output configuration is checked before and during each case.
The full run takes roughly half an hour, plus source hashing and package checks.
`--duration`, `--warmup` and `--settle` are available for controlled reproductions; record any change when comparing runs.

## Keep awake and restore

`run-a10.sh` holds `kde-inhibit --power --screenSaver` for the entire run.
Its wrapper rejects an inhibition error before starting the bench and propagates the bench exit status, since kde-inhibit itself does neither.
The wrapper forwards Ctrl-C and SIGTERM to the bench while keeping inhibition alive during output restoration.
The runner calls `SimulateUserActivity` before every case and periodically during waits.
It checks KScreen's dimming report every two seconds and stops if any output, including a disabled output, reports a value other than 100%.
It never repairs dimming by changing brightness or PowerDevil preferences.
A missing diagnostic, early player exit, KWin restart/log truncation, missing source telemetry, stale log, failed fullscreen placement, or wrong output setup also stops the run.
A failed run is marked `confounded` and produces no comparison table.

On normal exit, errors, Ctrl-C or SIGTERM, the runner terminates only its own player PID and restores the original output enable states, modes, positions, scales, rotations and mirror relationships.
It checks the restored configuration and retains `restore-command.json` and `outputs-original.json` for manual recovery if the session or machine dies before cleanup.
To retry that exact restoration, the main session can run:

```
python3 -c 'import json,subprocess,sys; subprocess.run(json.load(open(sys.argv[1])),check=True)' RESULTS/restore-command.json
```

The installed published Bino is never replaced: `/usr/bin/bino` remains the normal launcher throughout.
To stop using the candidate, stop the bench and use that launcher.
The private kit directory can then be removed after preserving the results elsewhere.

## Result and interpretation

`comparison.md` and `comparison.csv` contain one row per setup and paired published/candidate columns for KWin frames/second and drops/minute.
`kwinframes.py` adapts the supplied `a10-inputs/kwinframes.py` only to accept a log directory and return machine-readable results.
Its measure is unchanged: count KWin pageflip timestamps in each half-open `[start, end)` interval from `marks.csv`.
The original helper is included as `kwinframes-original.py`.
The kit waits for KWin's buffered CSV to reach the end mark before copying the complete interval rows.

Drops/minute is `max(0, source_fps - KWin_fps) * 60`, using ffprobe's rational source rate.
It is a presentation-deficit estimate, not an identity-based count of missing film frames.
KWin includes all presentations, so another window or an animated overlay can confound it; keep the desktop and pointer still while the bench runs.
The code keeps this distinction in the output table's explanation.

Each case retains the Bino log, exact command/environment, source observer CSV, candidate Bino frame-trace CSV, output snapshots and event counts beside the KWin rows.
`source.json`, the clip SHA-256, binary hashes and package versions identify the inputs.
The independent observer attaches to `QVideoSink::videoFrameChanged` without mapping the frame.
It records source PTS, GL client-memory texture uploads, DMA-BUF image imports and EGL image binds.
The GL events include all application textures, including UI; their PTS field is the most recently observed sink PTS, not an independently identified pixel payload.
NV12 imports produce one import per plane; do not equate that count with frames.
The candidate's own `cpu_upload` and `texture_import` events supply exact video-frame PTS and distinguish fallback from import.
Published Bino has no internal trace hook, so its common observer supplies that side of the diagnostic record.
Instrumentation performs no frame readback or forced GPU synchronization in the A10 run.
The two builds share the observer; the candidate additionally writes its internal diagnostic trace, so these are instrumented comparisons.

## Local validation

`python3 -m unittest test_kit test_inhibit` checks the half-open time boundaries, expected frame counts, deficit calculation, dimming negatives, missing/end-mark negatives, mode selection and restoration checks.
The inhibition wrapper has missing-service, exit-status and SIGTERM cleanup controls, including a real kde-inhibit run on an isolated D-Bus session without inhibition services.
The helper's fullscreen placement and telemetry are also exercised in isolated KWin sessions with the installed published and candidate packages.
The import observer's retained negative misses EGL 1.5 imports; the final observer sees both NV12 plane imports for each candidate frame.
The kit has not been run on the A10 by this lane.
