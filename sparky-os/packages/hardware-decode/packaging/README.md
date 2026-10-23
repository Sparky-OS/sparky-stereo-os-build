# ORDER 223 package cohort

Start from the signed published source package for each engine, retaining every earlier patch and the package's native Lean Code preservation plan.
`build-source.py` verifies the source archive hashes and adds only the reviewed decoder/routing patches and dependency floors.
The new `media-gpu-route` source builds its shared library, development adapter and diagnostic query using Debian's native source format and soname package convention.
`libplacebo-dmo` starts from the retained deb-multimedia source because this is its first edition build.
All changelogs use Daniel Ramos (Capitain Jack)'s packaging identity.
The source package retains the complete authored inputs and the release machinery.

`run-build.sh PACKAGE` requires the explicit SPARKY_* paths and image listed at its start.
It starts a four-CPU container with no GPU or desktop socket.
Dependencies resolve from the signed predecessor tree and the already staged cohort, at the edition's priority.
`stage.py WORK PACKAGE` stages the new `.dsc`, every file that `.dsc` names, binary archives, `.changes`, `.buildinfo` and `SHA256SUMS` under `WORK/out/PACKAGE`.
It never rewrites the published predecessor.

Build in dependency order: media-gpu-route, libplacebo, FFmpeg, mpv/libmpv, MLT, Qt Multimedia, Kdenlive, VLC, hardware support.
The FFmpeg i386 twin must come from the same new `.dsc` as amd64, with the same changelog and shared files.
`check-debs` and `check-link --previous-dir` must pass before staging.
The diagnostic builds in the earlier review are not release inputs.
Final qualification uses the installed archives, without diagnostic library or plugin overlays.

## Main session's A10 bench

The A10 is the main session's bench, not a lane endpoint.
The script is prepared here and is never executed on the A10 by this lane.
`a10-matrix.py --phase before --dry-run` prints the whole matrix and performs no subprocess, file write, package installation or screen change.
It has 216 film cases per phase, so the full before/after run is long.
Use `--select REGEXP` and a new `--output` for bounded batches while retaining the same before/after cases.
Each film has a four second launch period, a 60 second warm-up, and a 180 second recorded interval, followed by eight seconds between films.
Each new display setup has seven seconds to settle, 30 seconds before its idle window, then 120 seconds of recorded idle.
These windows follow the existing A10 matrix method.

The cases cover laptop only, TV only, and all four extended 2D/3D combinations, with playback on either active output.
Each uses the integrated path with the discrete renderer unused, discrete rendering through Mesa PRIME, and the untouched default, for Vulkan and GL.
The integrated Vulkan control uses Mesa's PCI selector with `!` to expose only that GPU to Vulkan.
The integrated GL control selects its PCI device without that Vulkan-only suffix.
The discrete PRIME control selects the connectorless discrete GPU while Carrizo still drives the screens.
No GPU is unbound, powered off or removed from the running desktop.
The script logs actual GPU choices; this control is not a claim that a second GPU was physically removed.

Supply the existing recorded 2D film, Life of Pi 3D and Coyote Falls 3D as `--film-2d`, `--film-3d` and `--coyote`.
The script uses installed mpv and libmpv's compiled default, without setting hwdec and without user configuration.
The native installed-package matrix separately qualifies Qt Multimedia, MLT and VLC.
A new frontend performance claim requires its own frontend run.
The source stream/frame declarations, mpv logs, IPC decoder/drop/stereo counters, output configuration, installed versions and 1 Hz machine log are retained.
KWin's per-frame logs are copied alongside monotonic-clock `marks.csv` windows.
Those logs supply physical presentation statistics; IPC source frame rate is not measured presentation FPS.

Before starting the bench, the main session enables `KWIN_LOG_PERFORMANCE_DATA=1` in its own KWin bench service and gives it a writable working directory.
The script requires that directory as `--kwin-log-dir`, checks both CSV headers and checks that the active output's log grows during playback.
It never restarts KWin or edits a service drop-in.
Use the existing bench drop-in rather than altering Daniel's ordinary session from a lane.
The exact modes are those in the reference A10 matrix, including the laptop anaglyph mode and the TV frame packing mode.
Missing modes stop execution rather than selecting a different raster.
The original enabled outputs, modes, positions, scales, priorities and mirror relationships are restored on normal exit, errors, Ctrl-C and SIGTERM.
A forced kill or machine failure cannot run cleanup; `outputs-original.json` retains the snapshot.

The main session installs the published cohort for `before`, then the new cohort for `after`, using the matching version manifest supplied with the staged results.
Install the whole dependency cohort together; do not mix one new codec or engine with older companions.
For a manual dependency sequence, use the shared routing runtime first, libplacebo next, the complete FFmpeg set including any installed i386 twin next, then mpv/libmpv, MLT, Qt Multimedia, Kdenlive, VLC and hardware support.
Install the corresponding development packages when compiling the test clients; HR companions are optional for playback and stay available beside the runtime archives.
The new engine dependencies enforce the FFmpeg cleanup and routing runtime floors, and Kdenlive enforces the new MLT floor.
For a before downgrade, the main session uses the retained published packages with APT's explicit `--allow-downgrades`; it checks the simulated transaction first.
This script never performs those installations itself.
The ISO input list is a build input, not an A10 package installation.

After copying the script, manifests and package cohort to the A10, the main session can run it locally or send the same script from the host:

```sh
python3 a10-matrix.py --phase before --host A10 --dry-run
python3 a10-matrix.py --phase before --host A10 --execute \
  --output /path/to/owned/bench --versions /path/to/a10-versions.json \
  --kwin-log-dir /path/to/kwin/working-directory \
  --film-2d '/path/to/2D film.mkv' --film-3d '/path/to/Life of Pi.mkv' \
  --coyote '/path/to/Coyote Falls.mkv'
```

Repeat the same selected cases with `--phase after` after the main session installs the candidate cohort.
All paths in the executed command are A10 paths.
Use the A10 desktop account; the runner supplies its normal runtime directory, user bus and wayland-0 socket when SSH has not exported them, and refuses missing sockets.
Keep the kernel and KWin build the same in both package phases, and announce the screen changes to Daniel before the main session runs the bench.
`--host` uses the main session's existing SSH alias and sends this one script over stdin.
No host name, account or credential is stored in the machinery.
Execution refuses a machine that is not the Lenovo A10 topology.

`a10-runtime-packages.json` lists the exact runtime companions to install together, including the FFmpeg libraries, Qt QML plugin, MLT data, Kdenlive data and VLC PipeWire plugin.
It excludes source, development, HR, documentation and debug archives from the playback transaction.
The main session first makes the reviewed repository copy available to APT, retains the edition pin and signed deb-multimedia source, and checks the transaction as root on its bench:

```sh
phase=after
mapfile -t cohort < <(python3 - "$phase" <<'PYTHON'
import json, sys
for package, version in json.load(open('a10-runtime-packages.json'))[sys.argv[1]].items():
    print(package+'='+version)
PYTHON
)
apt-get -s --allow-downgrades install "${cohort[@]}"
```

After Daniel approves the bench installation, the main session repeats that exact transaction without `-s`.
For the before phase, use `phase=before` with the retained published packages available, then the same script and film selections.
APT installs the dependency graph in order; the manual sequence above names the same layers.
The runtime list does not change the kernel, KWin or GPU drivers during the before/after player comparison.
