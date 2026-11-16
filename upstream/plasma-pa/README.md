# Virtual streams in KDE's Sound page and volume widget

This recipe prepares the edition's plasma-pa 4:6.7.4-1+stereo3d1+lc1 and holds its isolated proof rig and translation generator.
The package exposes optional virtual streams, repairs null-client handling and the recording selector, and adds translated labels.
No system PipeWire or WirePlumber default is supplied here.

From a lane folder with `src/plasma-pa` on the candidate and this build-tree clone at `src/sparky-stereo-os-build`:

```sh
export DOCKER_HOST=unix:///path/to/lane/docker.sock
bash src/sparky-stereo-os-build/upstream/plasma-pa/rig-setup.sh "$PWD"
bash src/sparky-stereo-os-build/upstream/plasma-pa/rig-build.sh

docker exec --user 1000:1000 pa19-rig dbus-run-session -- bash /lane/src/sparky-stereo-os-build/upstream/plasma-pa/rig-case.sh published 1
docker exec --user 1000:1000 pa19-rig dbus-run-session -- bash /lane/src/sparky-stereo-os-build/upstream/plasma-pa/rig-case.sh candidate 1
docker exec --user 1000:1000 pa19-rig dbus-run-session -- bash /lane/src/sparky-stereo-os-build/upstream/plasma-pa/rig-case.sh candidate 1.25
docker exec --user 1000:1000 pa19-rig dbus-run-session -- bash /lane/src/sparky-stereo-os-build/upstream/plasma-pa/rig-case.sh candidate 1 applet
docker exec --user 1000:1000 pa19-rig dbus-run-session -- bash /lane/src/sparky-stereo-os-build/upstream/plasma-pa/rig-case.sh candidate 1 hotplug
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

`make-source.py DSC WORK` prepares Debian's signed 4:6.7.4-1 descriptor (pinned by SHA-256), the accepted product patch, and the translation patch, then creates an authored source and a +stereo3d1+lc1 source through Lean Code.
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
