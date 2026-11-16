# Virtual streams in KDE's Sound page and volume widget

This recipe folder currently holds the isolated proof rig and the edition's translation generator.
The change is a tested source candidate on Plasma 6.7.4; Debian packages are a later milestone.
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
The recipe compiles and reads these catalogues for the prototype only; no package carries them yet.
A successor package must apply the patch last in its Debian series and prove its installed catalogues.
