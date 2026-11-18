# The host side of the proofs (lane pje-office-2, ORDER 18 milestone 2)

These are the scripts the lane ran on the build machine; the proofs themselves are the scripts one folder up (`tests/rig/*.sh`, `tests/installer.sh`, `watcher/test_watch.py`), which run inside the containers.
They name the lane's folders (`/var/tmp/pje-office-18`, `/K3D/partners/queue/pje-office-2`) and its Docker socket: change those three paths for another lane.
Images, in this order: `mk-build-image.sh` (Debian testing with the edition's published tree and its pin, then the KF6 and Qt 6 development packages, `devscripts`), a runtime image (the packages of `make-installed.sh`'s first lines), `make-installed.sh` (a flat repository of the built packages with the edition's origin, the install-time download hook of sparky-stereo-apt, then `apt-get install sparky-pjeoffice`, which fetches CNJ's ZIP).
Builds: `build-in-container.sh` of each package recipe (see its README), `build-appcenter.sh` and `build-appcenter-2.sh` (the second pass gives the build record its buildinfo).
Runs: `run-green.sh` (installer and watcher tests on the files of the built .deb), `run-mut.sh NAME` (a red control), `run-rig.sh NAME MODE` (signing), `run-cutter.sh`, `run-plasma.sh NAME [LOCALE]` (needs the network once for the locale), `run-dolphin.sh`, `run-entry.sh CASE`, `run-life.sh`, `run-trust.sh`, `sparky-main-test.sh` (the SparkyLinux-main branch's install block with the real file).
`archive-sources.json` is the link gate's archive configuration (its keyrings are dearmoured copies of Debian's, deb-multimedia's and the edition's).
Nothing of CNJ's is kept anywhere: the ZIP is fetched into a container or the scratch folder and deleted with it.
