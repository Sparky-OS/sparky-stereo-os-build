# VLC Stereo: the packages

Two Debian packages, built from Debian testing's `vlc` source package plus our patches, installed beside Debian's VLC and sharing no file with it:

- `vlc-stereo`: the program (`/usr/bin/vlc-stereo`), its libraries and plugins in `/usr/lib/x86_64-linux-gnu/vlc-stereo/` (found through RPATH), its data in `/usr/share/vlc-stereo/`, its menu entry `vlc-stereo.desktop`. Settings in `~/.config/vlc-stereo`.
- `vlc-stereo-plugin-pipewire`: the PipeWire audio output of Debian's `vlc-plugin-pipewire` 3-4 (Rémi Denis-Courmont, GPL-3+), copied for VLC Stereo with our change (float samples, resampling once to the rate of the graph, a buffer multiplier). Debian's own package and the original VLC are not touched.

## What is in this folder

| Path | What |
|---|---|
| `../0001-*.patch` to `../0038-*.patch` | the changes to VLC 3.0.24, applied in order; 0020 fixes stereo overlay sizing, 0021 adds native Wayland video inside the main Qt window, 0022 to 0026 are the stereo policy, the window width and the closing fixes of +stereo3d7 and +stereo3d8, 0027 to 0038 those of +stereo3d10 (each view at its own resolution, every packing with both eye orders, frame sequential pairs, the minimal view, the first picture, the 3D options' translations) |
| `patches/base/` | the three changes of the released VLC HiFi 3D (3d1) that the series builds on |
| `../debian-branding/vlc-stereo-name.patch` | the name "VLC Stereo" (menu entries, window titles, About, MPRIS identity); a Debian patch, not a commit for upstream |
| `patches/vlc-stereo-side-by-side.patch` | what lets it run beside the original: user directories `~/.config/vlc-stereo`, Qt settings, MPRIS bus name, window class, application id |
| `patches/pipewire/` | our change to the source of Debian's `vlc-plugin-pipewire` 3-4 (the upstream tarball) |
| `gen-debian.py`, `files/` | turn Debian's `debian/control` and `debian/rules` into the packaging of the two packages (private directories, RPATH, desktop and icon names, the plugin built from the copied source, maintainer scripts for the plugin cache) |
| `build-lc.sh`, `build-lc-in-container.sh` | the build since +stereo3d10: the published source package of the version before, the new patches after the last stereo patch, the changelog entry of the version from `changelog`, then Lean Code and the link and start gate |
| `build.sh`, `Dockerfile` | the build up to +stereo3d6, from Debian's `vlc` source (Debian testing has since moved to 3.0.24-3 with a Qt 6 interface, which 0021 does not support yet) |
| `make-branding.sh`, `make-sbs.sh` | how the two Debian patches were generated (kept for regeneration; they expect the paths of the author's workspace) |

Debian's `debian/patches`, copyright and changelog stay; only the packages, control fields (Maintainer, Original-Maintainer, Homepage as in `sparky-os/repo/provenance.sh`), the changelog entry and the build dependencies our change needs (`libstereo-declare-dev`, `libpipewire-0.3-dev`) differ.

## Build a new version

`build-lc.sh WORK PREVIOUS_DIR` builds `VERSION+lc1` (default `3.0.24-1+stereo3d10`) from the published `BASE` source package (default `3.0.24-1+stereo3d9`, in `$SPARKY_REPO_DIR/source`) and the patches `../0NNN-*.patch` from `FIRST` on (default 27), in the Lean Code migration image `sparky-lc-migration:20261020`, with the edition's repository pinned at 1001 and deb-multimedia's `forky` source, so the build depends on the libraries the edition installs. `PREVIOUS_DIR` holds the `BASE+lc1` debs for the link and start gate. `WORK` then holds the source package (`s/`), the Lean Code source and the debs (`lc/`), and the logs.

## Rebuild from a clean container (up to +stereo3d6)

1. A build context with the Dockerfile and the two `libstereo-declare` packages of the Sparky Stereo repository:

```
mkdir -p ctx/repo
cp vlc-stereo-packaging/Dockerfile ctx/
cp $SPARKY_REPO_DIR/libstereo-declare1_*.deb $SPARKY_REPO_DIR/libstereo-declare-dev_*.deb ctx/repo/
docker build -t vlc-stereo-build ctx
```

The image is a freshly updated `debian:testing` (record its Qt, FFmpeg and PipeWire versions in the notes of the build: `dpkg -l libqt5core5t64 libavcodec63 libpipewire-0.3-0t64`).

2. The build, as your own user, with this folder (`sparky-os/upstream/vlc`) mounted read-only (about 25 minutes on 5 cores):

```
mkdir -p work out
docker run --rm --user $(id -u):$(id -g) -e VER=3.0.24-1+stereo3d6 \
  -v $PWD/sparky-os/upstream/vlc:/src:ro -v $PWD/work:/work -v $PWD/out:/out \
  vlc-stereo-build bash /src/vlc-stereo-packaging/build.sh
```

`out/` then holds the two packages, the `.changes` and `.buildinfo`, and the Debian source package of the build: `vlc_<version>.dsc`, `vlc_<version>.debian.tar.xz`, `vlc_3.0.24.orig.tar.xz` and its `.asc` (check it with `dpkg-source -x vlc_<version>.dsc` in an empty folder). The source package is made before the binary build, so that no build product is in it.

3. The edition's packages carry their provenance: run `sparky-os/repo/provenance.sh` on the two `.deb` files (Maintainer, Homepage and the credit stanza in the copyright files), then copy them, and the source package files into `$SPARKY_REPO_DIR/source/`, into the repository.

## Notes

- Since +stereo3d6, Wayland sessions use an integrated native video child and require `qtwayland5`. Keep `embedded-video=1` for the self-contained player. X11 remains available when explicitly selected, with its earlier embedded-child stereo limitation.
- `tests/t-startup.py`, run under `dbus-run-session`, checks menu startup, coexistence and file forwarding in separate configuration directories. `tests/check-embedded.py` checks the private KWin fixture captures for complete eye views, ordinary controls and mono restoration.
- `build.sh` needs the network: it runs `apt-get source` for `vlc` and `vlc-plugin-pipewire`.
- The version is the Debian version of the source with our suffix: `3.0.24-1+stereo3dN`. A new Debian `vlc` source may need the patches refreshed (`quilt push -a` in `build.sh` stops at the first patch that does not apply).
- No `-dev` package, no `Conflicts`, `Replaces` or `Provides`: the packages must never replace anything of Debian's VLC.
