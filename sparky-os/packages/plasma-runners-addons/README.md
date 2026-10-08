# Plasma runner currency refresh

Rebuild Debian testing's kdeplasma-addons 4:6.7.4-1 with currency updates triggered
by a currency conversion query. The edition keeps the converter enabled.

The patch comes from the KDE v6.7.4 source clone, branch
`partner/kde-desktop-defaults`, commits `09021da` and `b7585f0`.
It changes the owning converter runner and adds its network regression test.
The upstream URL, currency parsing, conversion library and translations stay
with KDE. Current queries receive results after the rates arrive; an obsolete
query receives no late results.

Run `build.sh` inside a freshly updated Debian testing build container, with
`OUT` set to a pending package directory and `BUILD_ROOT` to disposable scratch.
Debian's rules and existing patches are retained. The package version is
`4:6.7.4-1+stereo3d1`. Debian tests are excluded by its nocheck profile; the KDE
runner tests and kde-ci-local run separately before handback.

The build produces the source package and all Debian binary packages, including
`plasma-runners-addons` and its exactly versioned `kdeplasma-addons-data` dependency.
Apply the edition's existing `sparky-os/repo/provenance.sh` before staging the
binary packages to record Daniel and Debian's original maintainer.

The lane's rootless container setup uses PRoot to emulate package-manager root
inside a disposable filesystem. Its kernel UID remains the invoking user's;
files are owned by that user and can be cleaned. No host packages are installed.
