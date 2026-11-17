# Virtual streams in KDE's Sound page and volume widget

This recipe prepares the edition's plasma-pa 4:6.7.4-1+stereo3d2+lc1 and holds its isolated proof rig and translation generator.
The package exposes optional virtual streams, repairs null-client handling and the recording selector, and adds optional input monitoring and a combined recording source. Both routing features start off. Their controls, failures and shared-microphone warning have English messages and nine translated catalogues.
No system PipeWire or WirePlumber default is supplied here.

## Build from Debian's source

The two producers start their own disposable containers from a pinned public Debian image. They require no retained lane image or running container. The image can be overridden with IMAGE; CONTAINER_NAME selects each container's name and CPUS defaults to two. Both forward the full build-provenance argument array, including the reproducible-source helper mount.

Supply Debian's plasma-pa_6.7.4-1.dsc and the archives it names in SOURCE_DIR. The descriptor is pinned by SHA-256; dpkg-source verifies the archive checksums. Use a fresh work directory for each producer:

```sh
bash RECIPE/package.sh SOURCE_WORK SOURCE_DIR
SPARKY_REPO_DIR=SIGNED_REPO SPARKY_LC_ARCHIVE_DIR=ARCHIVE_DIR \
  bash RECIPE/build.sh BINARY_WORK SOURCE_WORK/prepared/lc PREVIOUS_DEBS_DIR
```

SOURCE_WORK/prepared contains both authored and Lean Code sources. BINARY_WORK/build contains binaries, buildinfo, changes and the complete build record. The binary producer reads the supplied source's changelog date, builds from its DSC without repacking it, runs the native validator, verifies all LC payloads/HR companions and runs the archive-qualified link gate. It installs its own build tools and the source's Build-Depends. Inputs, build tree and signed archives are mounted read-only; only the named output is writable, and outputs are returned to the caller's UID/GID.

ARCHIVE_DIR/sources.json names the public signed APT archives and their public keyrings as described in sparky-os/lean/archive.md. The edition's signed snapshot is available at /repo. Keyrings supplied in ARCHIVE_DIR use /archive paths inside the container; the base image supplies Debian's keyring. The binary container enables the namespace operations needed by the nested bubblewrap gate, whose own root is isolated and capabilities dropped. No desktop session or sound device is mounted.

Reproduce the source with tests/repro-source.py BASE_DSC PREPARED WORK BUILD_RECORD inside a disposable container carrying fakeroot, libfaketime, devscripts, the source's debhelper addon (dh-sequence-kf6) and the producer's tools. This is a proof driver, not a producer: it compares authored and LC descriptors/archives across clocks, time zones and umasks, then checks an actual dpkg-buildpackage -S repack. Its source date comes from the build record. The static supply-chain/test-wiring.sh must finish ALL PASS before hand-back.

## Installed audio and GUI proofs

Use a throwaway container with Plasma, PipeWire, pipewire-pulse, WirePlumber, null devices, Xvfb, a private D-Bus/accessibility bus, Python's GI/AT-SPI/Pillow modules and xdotool. Disable core dumps; do not mount a person's display, audio runtime or hardware devices. Run probes as an unprivileged user. Each WORK must be new.

After installing the built runtime and HR packages, remove prototype prefixes /opt/order19 and /opt/order19b and set PA19_INSTALLED=1. Otherwise prototype probes use /opt/order19b. Run one desktop case at a time:

```sh
PA19_INSTALLED=1 PA19_CHECK_NAMES=1 dbus-run-session -- python3 RECIPE/rig-route-ui.py WORK 1
PA19_INSTALLED=1 PA19_CHECK_NAMES=1 dbus-run-session -- python3 RECIPE/rig-route-ui.py WORK 1.25
PA19_INSTALLED=1 PA19_RATE=96000 dbus-run-session -- python3 RECIPE/rig-routes.py WORK
```

The page probe checks actual controls, ordinary stream routing, window lifetime, missing targets and the shared-microphone warning. CHECK_NAMES rejects the helper names in visible labels. Streams supply translated application.name, application.description and media.name; owned stream delegates use their supplied description on both the page and widget, instead of prepending the process's client name.

Install the accepted system-audio-defaults package before the 96 kHz row. Read PipeWire Format and pw-top rather than PulseAudio's nominal stream rate. PA19_CHANNELS=1 checks a mono microphone. PA19_FAILURE_MODE=missing or exit tests missing/exiting helpers. PA19_LATENCY_MODE=1 measures a simultaneous four-channel synthetic graph, not physical latency. PA19_NATIVE=1 uses an extracted PulseAudio server/modules under /work19/native/root for a private native-server case.

rig-case.sh installed SCALE [applet|hotplug] checks the original virtual streams and routing. PA19_RESULT selects fresh evidence, and PA19_SCREEN_HEIGHT=2800 PA19_WINDOW_HEIGHT=2600 gives a tall full-page capture. PA19_ENABLE_ROUTES=1 keeps owned routes active in the hotplug case; with PA19_APPLET_OWNED=1 it checks the actual widget's owned Listen menu. The new output takes the default while explicitly targeted bridge/Listen/combined routes stay selected.

Combined Recording literally adds the output mix and microphone. If Listen sends that microphone to the same output, both paths include it; the translated warning explains this. Internal combined capture controls point to their combined-source settings. The source has low session priority and keeps the established default input.

make-translations.py and make-route-translations.py generate the virtual-stream and audio-routing PO patches. The routing generator consumes the source after the virtual-stream patch. check-route-catalogues.py reads all routing keys from the built MO files. Run translations-shipped.py with both patch names against the binaries and its --gettext mode under all nine generated translated locales in the installed rig.

Debian disables build-time Appium tests; the successor prints that policy and the missing prerequisites rather than silently calling the suite tested. The real upstream applettest runs in KDE CI as described below.

## CI without station devices

The current Selenium runtime pulls master KWin and plasma-workspace transitively, even when this branch declares Plasma/6.7 directly.
That workspace requires Wayland, while its KWin renderer requires a render device.
For this two-dimensional applet test, `ci-headless.sh` starts Weston headless with Pixman and software Qt Quick; it selects Selenium's supported external-compositor mode and disables its optional video recorder.
`ci-app-launch.sh` starts the archive's desktop services at their actual test prefix and warms the portal before execing the exact original app command.
The app keeps `QT_FATAL_WARNINGS=1`; no assertion or test is removed.

Run kde-ci-local with `--manual-session --build-setup PATH/ci-headless.sh --job-mount PATH:/pa19-ci:ro`, where PATH is this recipe's absolute directory.
Use `--job-image JOB=IMAGE` for refreshed images; a stale Qt Next image can lack symbols its downloaded Frameworks libraries require.
The images must contain Weston and the distribution's runtime libraries required by the KDE artifacts.
This proves the widget under a private software Wayland compositor; it does not test KWin-specific protocols or a hardware renderer.

