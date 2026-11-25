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

The lane exports a clean Debian base filesystem and extracts it as the invoking
user. Its imported Docker image has files writable by that user. Fakeroot
supplies the package manager's expected identity while the actual kernel UID
stays 1000. APT updates testing before installing build dependencies. The
package build and tests run as that user; no host packages are installed.

## Weather cohort build

Run `build-weather.sh WORK INPUT PREVIOUS ARCHIVE PUBLISHED` from a clean recipe commit.
Set `IMAGE` to the amd64 builder with the frozen build dependencies installed.
`WORK` is a new directory.
`INPUT` holds the pinned source descriptor and its files, the stereo-layer clone, or the generated `icons/` tree, according to the source being built.
For stereo-layer, `LAYER_REVISION` names the full source commit that is exported.
`PREVIOUS` holds the published predecessor binaries and `PUBLISHED` is the read-only edition tree.
`ARCHIVE` contains the signed snapshot configuration and package bytes for the link gate.
Set `PUBLISHED_SIBLINGS` to a list of baseline package files as seen below /round.
Set `SIBLINGS_DIR` to the local sibling packages grouped in directories named after their sources.
For the weather applet build, the isolated currency test needs iproute2 in the builder or its Debian archives in `IP_FIXTURE_DIR`.
The build records the committed recipe and leaves the descriptor, source files, binary packages, changes, buildinfo and build record in `WORK`.
