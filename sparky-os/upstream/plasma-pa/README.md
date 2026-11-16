# Virtual streams in KDE's Sound page and volume widget

This recipe prepares the edition's plasma-pa 4:6.7.4-1+stereo3d2+lc1 and holds its isolated proof rig and translation generator.
The package exposes optional virtual streams, repairs null-client handling and the recording selector, and adds optional input monitoring and a combined recording source. Both routing features start off. Their controls, failures and shared-microphone warning have English messages and nine translated catalogues.
No system PipeWire or WirePlumber default is supplied here.

From a lane folder with `src/plasma-pa` on the candidate and this build-tree clone at `src/sparky-stereo-os-build`:

```sh
export DOCKER_HOST=unix:///path/to/lane/docker.sock
bash src/sparky-stereo-os-build/sparky-os/upstream/plasma-pa/rig-setup.sh "$PWD"
bash src/sparky-stereo-os-build/sparky-os/upstream/plasma-pa/rig-build.sh

docker exec --user 1000:1000 pa19-rig dbus-run-session -- bash /lane/src/sparky-stereo-os-build/sparky-os/upstream/plasma-pa/rig-case.sh published 1
docker exec --user 1000:1000 pa19-rig dbus-run-session -- bash /lane/src/sparky-stereo-os-build/sparky-os/upstream/plasma-pa/rig-case.sh candidate 1
docker exec --user 1000:1000 pa19-rig dbus-run-session -- bash /lane/src/sparky-stereo-os-build/sparky-os/upstream/plasma-pa/rig-case.sh candidate 1.25
docker exec --user 1000:1000 pa19-rig dbus-run-session -- bash /lane/src/sparky-stereo-os-build/sparky-os/upstream/plasma-pa/rig-case.sh candidate 1 applet
docker exec --user 1000:1000 pa19-rig dbus-run-session -- bash /lane/src/sparky-stereo-os-build/sparky-os/upstream/plasma-pa/rig-case.sh candidate 1 hotplug
docker stop pa19-rig
docker rm pa19-rig
```

Run one case at a time; each gets a private bus, Xvfb server and audio session.
The published branch uses installed Debian plugins; the candidate uses the `/opt/order19` manifest paths.
The UI scripts operate the actual settings page and applet and independently read selected server routes.
Set `EXPECT_VISIBLE=1` in the published page case for a negative assertion that must fail on the missing virtual playback row.
The hotplug case uses only synthetic null devices and the existing edition hook from this checkout.
It verifies USB headset, USB speaker and Bluetooth output defaults, and preserves an explicitly targeted client bridge.
Captures and logs go to the lane's `evidence/`, never this repository.
Use a fresh container for a clean rebuild; each case gets a fresh home, and the page test copies its saved enabled key into the evidence.

`make-translations.py SOURCE PATCH` generates `sparky-os/translations/plasma-pa-virtual-streams.po.patch` for the nine translated locales beside English.
The source producer applies this patch last in its Debian series.
Run `sparky-os/tests/translations-shipped.py --only plasma-pa-virtual-streams.po.patch STAGE` to read the built package's catalogues, then its `--gettext` mode with the absolute patch path in the installed rig with the nine real locales generated.

## Debian successor

`make-source.py DSC WORK` prepares Debian's signed 4:6.7.4-1 descriptor (pinned by SHA-256), the accepted product patch, and the translation patch, then creates an authored source and a +stereo3d2+lc1 source through Lean Code.
It takes SOURCE_DATE_EPOCH and SOURCE_DATE_RFC2822 from the committed recipe.
`package.sh` supplies these dates and host provenance to the lane's prepared container; `build.sh` builds the resulting descriptor and runs the native unit test and archive-backed package checks.
The container must provide the lane at /lane, disposable work at /work19, the signed edition repository at /repo, the HTTPS-only APT helper and CA bundle, with two CPUs and core dumps disabled.
Its /work19/archive/sources.json explicitly names the signed Debian, deb-multimedia and edition sources and their public keyrings.

Debian's rules disable build-time tests; the successor retains that policy and prints the missing Appium prerequisites instead of silently treating the suite as run.
The real upstream applettest needs selenium-webdriver-at-spi-run, Appium and its Python bindings, a private compositor and an accessibility bus with the service startup expected by the runner.
The native validator is run separately, as are the actual page and applet routing checks.
After installing the built .deb, use `rig-case.sh installed SCALE [applet|hotplug]`; this mode uses the system plugin and QML paths and never the prototype /opt prefix.
Remove the prototype prefix in that container before testing, so a stray import path cannot mask an installation error.
`rig-compare.py EVIDENCE installed` checks unchanged page content against the published control at both scales.

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

## Input monitoring and combined recording

`rig-routes.py WORK` checks the KDED interface and actual audio content in a private bus/session. `rig-route-ui.py WORK SCALE` drives the installed Sound page, ordinary stream routing, close/reopen, missing targets and the shared-microphone warning. Run both with `PA19_INSTALLED=1` after removing `/opt/order19` and `/opt/order19b`; otherwise they use the prototype prefix. Each WORK must be new.

```sh
PA19_INSTALLED=1 PA19_RATE=96000 dbus-run-session -- python3 RECIPE/rig-routes.py WORK
PA19_INSTALLED=1 dbus-run-session -- python3 RECIPE/rig-route-ui.py WORK 1.25
```

Run these commands only inside the device-free rig, as its unprivileged test user. Install the accepted system-audio-defaults package before the 96 kHz case. The native-server case uses `PA19_NATIVE=1` and the extracted PulseAudio 17.0 binary and modules under `/work19/native/root`; `PA19_CHANNELS=1` checks a mono microphone. `PA19_FAILURE_MODE=missing` or `exit` tests missing/exiting PipeWire helpers. `PA19_LATENCY_MODE=1` measures the synthetic graph with a simultaneous four-channel capture; it does not measure hardware latency. Inspect the actual PipeWire Format and pw-top rows rather than PulseAudio's nominal stream sample specification.

Combined Recording literally adds the selected output mix and microphone. If Listen sends that microphone to the same output, both paths include it; the page warns about this in the selected language. Internal combined capture streams direct their routing controls to the combined-source settings, where all contributors stay consistent. The new source has low session priority and keeps the established default input.

Set `PA19_ENABLE_ROUTES=1 PA19_APPLET_OWNED=1` for the applet case to check its actual owned Listen menu updates both saved preferences and the server target. Set `PA19_ENABLE_ROUTES=1` for the hotplug case to keep explicit monitoring and combined routes active while the synthetic newly connected outputs take the default. `PA19_RESULT` selects a fresh evidence directory. For a taller full-page virtual-stream capture use `PA19_SCREEN_HEIGHT=2800 PA19_WINDOW_HEIGHT=2600`.

`make-route-translations.py SOURCE PATCH` generates `plasma-pa-audio-routes.po.patch` after the virtual-stream patch. `check-route-catalogues.py DEB OUTPUT_JSON` reads all 29 routing keys in each built translated catalogue. The shared translations-shipped gate also compares every added translation with the generated patch; run its real `--gettext` mode under generated locales in the installed rig.

`repro-source.py BASE_DSC PREPARED WORK BUILD_RECORD` freezes the build record's source date and compares authored and Lean Code descriptors/archives across clocks, time zones and umasks, then checks an actual `dpkg-buildpackage -S` repack. Retain that build record's recipe commit even when later documentation commits update this recipe.
