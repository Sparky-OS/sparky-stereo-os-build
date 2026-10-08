# The edition's media stack on deb-multimedia: FFmpeg and mpv

Sparky Stereo OS builds its FFmpeg and mpv on **deb-multimedia's source packages** (`ffmpeg-dmo`, `mpv-dmo`), with our stereo 3D patches on top, as `+stereo3dN` versions (Daniel: "we should patch multimedia-deb ffmpeg, not debian's"). Package names, sonames and the epoch are deb-multimedia's, so what installs against deb-multimedia's FFmpeg installs against ours. This folder holds everything needed to **redo the port for each deb-multimedia release**: the patches, the packaging changes, the build and proof scripts, the proof rig and the Dockerfiles. The development repository (`/K3D/temp/sparky-os/repo`, made by `repo/make-repo.sh`) holds the packages and, in `source/`, the source packages.

Built 2026-10-07/08 (media-on-dmo lane):

| source package | deb-multimedia | ours |
|---|---|---|
| `ffmpeg-dmo` | `10:9.0.2-dmo1` | `10:9.0.2-dmo1+stereo3d2` (amd64 and i386) |
| `mpv-dmo` | `1:0.41.0-dmo9` | `1:0.41.0-dmo9+stereo3d1` (amd64) |

## What is in it

```
ffmpeg/patches/        nine patches (series lists ours only): frame packing SEI persistence for H.264, HEVC, VVC, the
                       side data preference of the display orientation SEI, and their FATE tests (upstream pull requests
                       24628 and 24643)
ffmpeg/packaging.diff  debian/control and debian/rules: no --enable-libfdk-aac, no --enable-nonfree, no libfdk-aac-dev;
                       the build profile pkg.ffmpeg-dmo.fdk turns them back on (for sparky-stereo-ffmpeg-fdk)
ffmpeg/changelog.in    the changelog entry (placeholders @VERSION@, @DMOVERSION@, @DATE@)
mpv/patches/           thirty-two patches: eight upstream commits after 0.41.0 that the others build on (the stereo 3D
                       layout from the stream's side data, upstream pull request 18490 and its follow-ups) and twenty-four
                       of ours (the automatic unpacking filter, the declaration to KWin through libstereo-declare, the video
                       layer under the window surface on Vulkan and OpenGL, per-eye placement, per-view interpolation,
                       the sphere projection as track-list/N/demux-projection)
mpv/packaging.diff     debian/control and debian/rules: build with libstereo-declare-dev (-Dstereo-declare=enabled)
mpv/mpv-dmo-0.41.0-stereo3d1.bundle   the thirty-two patches as a git branch on mpv 0.41.0 (for upstream and for the offer)
mpv/changelog.in       the changelog entry (placeholders @VERSION@, @DMOVERSION@, @FFMPEG@, @DATE@)
debdiffs/mpv-dmo.debdiff   deb-multimedia's mpv-dmo to ours, as a debdiff: the material of the offer to deb-multimedia
scripts/port.sh        step 1 of a new release: deb-multimedia's source package becomes ours (see below)
scripts/               the build and proof scripts as they ran (they expect /w, the work folder, mounted in the container)
scripts/rig/           the mpv proof rig: headless Stereo KWin in a container, mpv on its Wayland socket, captures of both
                       eyes by KWin's ScreenShot2, the Wayland debug log; LEFT-red / RIGHT-blue clips (mkclips*.py)
docker/                the Dockerfiles of the build environments, the proof images and the rig
```

## Redoing the port for a new deb-multimedia release

Everything runs in containers as the user (`--cpus 4` at most, never sudo, never on the host; `/tmp` is wiped at boot, so build trees go to a disk folder). `W` is the work folder, mounted as `/w`.

1. **Fetch deb-multimedia's source.** `docker/Dockerfile.base` is a debian:testing with deb-multimedia configured (`scripts/dmo-setup.sh`: its repository for `forky` and its keyring package). `scripts/fetch-src2.sh` runs `apt-get source --download-only ffmpeg-dmo mpv-dmo` into `/w/src`. Read the new `debian/changelog` of both: new binary packages or sonames mean the dependents (`libavcodec63` ...) change too.
2. **Port.** `scripts/port.sh ffmpeg /w/src/ffmpeg-dmo_X.dsc REVISION /w/srcpkg` (and `mpv ... FFMPEG_VERSION`) unpacks the source without its patches, adds ours after deb-multimedia's in `debian/patches/series`, applies `packaging.diff`, puts the changelog entry on top and writes the source package `+stereo3dREVISION`. It checks that every patch applies, in order. A patch that no longer applies: unpack the tree, `quilt push -f`, fix the hunk, `quilt refresh`, copy the refreshed patch back into `ffmpeg/patches` or `mpv/patches`. A `packaging.diff` that no longer applies: redo the same few lines by hand (`debian/rules`: drop the two options and add the profile block; `debian/control`: `libfdk-aac-dev <pkg.ffmpeg-dmo.fdk>`). Checked on 2026-10-08: `port.sh` on `ffmpeg-dmo 10:9.0.2-dmo1` and `mpv-dmo 1:0.41.0-dmo9` gives `debian/` trees identical to the ones built and proven (control, rules, patches and series; the changelog differs only in its history).
3. **Build.** FFmpeg: `docker/Dockerfile.ffbuild` (amd64) and `Dockerfile.ffbuild386` (a native i386 container, built on `Dockerfile.base386`) install deb-multimedia's build dependencies and then purge libfdk-aac, so the build proves it does not need it. `scripts/build-ff.sh` / `build-ff386.sh` run `dpkg-buildpackage -B` (about 16 minutes each on 4 processors, 33 to 35 CPU minutes). `scripts/make-srcpkg-ffmpeg.sh` makes the source package from the edited tree. mpv: `Dockerfile.mpvbuild`, then `Dockerfile.mpvbuild2` (our FFmpeg development packages and `libstereo-declare-dev` on top), `scripts/build-mpv.sh`. Never `docker pull --platform` an existing tag: with the classic image store it re-points the tag (it turned `debian:testing` into the i386 image once); `Dockerfile.base386` builds the i386 base under its own tag.
4. **Prove.** FFmpeg, from a fresh container with only our packages installed (`docker/Dockerfile.ffours`; the baseline is deb-multimedia's unpatched build, `Dockerfile.ffdmo` and `ffdmo2`):
   - `scripts/ffcheck.py /clips`: the 81 mark checks (every clip of the rig, one and four decoder threads: the Stereo 3D side data must be on exactly the frames the stream says, with the right type and eye order). Ours: 81 of 81 on amd64 and on i386. The baseline fails 49 of 81, so the check can fail.
   - `scripts/fate-ffmpeg.sh`: FATE in the patched tree (`fate-h264 fate-hevc fate-vvc`, 457 tests, the ten tests the patches add among them). All pass but `h264-bsf-redundant-pps-mov`, whose sample is not in the sample folder (also so for the unpatched tree).
   - `scripts/fate-negctl.sh`: the command lines of four of the new FATE tests against the reference files, with the packaged binaries: ours match all four, deb-multimedia's unpatched build differs on all four.
   - `scripts/framemd5.sh`: the md5 of every decoded frame, one and four threads, ours against the baseline: identical on 47 of the 48 clips; the 48th (`both-sei-and-stereomode.mkv`, a Matroska StereoMode and an SEI on one stream) does not decode with the unpatched build (error -17, two Stereo 3D entries on a frame) and decodes with ours.
   - `ffmpeg -encoders`: FFmpeg's own `aac` and no `libfdk_aac`; `ffmpeg -L` says GPL, not "nonfree parts compiled in".
   - Exports of the seven libraries (`nm -D --defined-only`) identical to the previous build's, and the only change in the package metadata is that `libavcodec63` no longer depends on `libfdk-aac2`.

   mpv: `scripts/run-mpv-proofs.sh IMAGE PREFIX [mepi]` runs the rig (m: the matrix of the three outputs `dmabuf-wayland`, `gpu-next`, `gpu`; e: OpenGL/EGL contexts; p: per-eye placement; i: interpolation) against the mpv of a rig image (`Dockerfile.rig` with `rigours` for our packages and `rigdmo` for the baseline); `scripts/ctl2d.sh` is the 2D control (a 2D clip must give the same pixels as the baseline: 0 differing pixels); `scripts/rig-summary.py` counts. Each run is judged from the pixels and the Wayland log, never from the words in a picture.
5. **Into the repository.** Debs and sources into `repo/` and `repo/source/`, the previous `+stereo3d` files to `repo-superseded/`, then `repo/make-repo.sh` (it stamps the provenance, indexes `Packages` and `Sources`, writes the `Release`). `scripts/promote.sh` is the script of the first promotion (its file lists are specific to that day).
6. **What apt does with it.** `scripts/fresh-check.sh` (a fresh container with the edition's pins and the repository: the candidates and the simulations for Blender, OBS, VLC, HandBrake, Kdenlive, the `-dev` packages and the i386 libraries), `scripts/vm-step1.sh` to `vm-step6.sh` (the same in the development VM; `vmssh.sh` and `sparky-vm-noaudio.sh` run the VM without touching the desktop's audio or display). After a release, rerun `apt/make-only-ours.py` and rebuild `sparky-stereo-apt`: its pins block deb-multimedia's and Debian's builds of every package the repository ships.

## Why FFmpeg has no Fraunhofer AAC

deb-multimedia's rules configure `--enable-nonfree --enable-libfdk-aac` on a GPL build. FFmpeg's `LICENSE.md` calls such a binary unredistributable, and `ffmpeg -L` says so ("nonfree parts compiled in"). Ours leaves both out, with the build dependency and the `libfdk-aac2` dependency, and is otherwise configured as deb-multimedia configures it (GPL version 3, every other library). Whoever wants Fraunhofer's encoder runs `sparky-stereo-ffmpeg-fdk` (`packages/sparky-stereo-ffmpeg-fdk`), which builds the same source with `-Ppkg.ffmpeg-dmo.fdk` on their own computer, for that computer only.

## Offering it to deb-multimedia

The mpv debdiff (`debdiffs/mpv-dmo.debdiff`) is the offer to Christian Marillat; the draft e-mail is in the media-on-dmo lane's folder and goes out when Daniel has read it. The FFmpeg offer waits for the upstream merges (pull requests 24628 and 24643), so that deb-multimedia ships patches FFmpeg already has; until then the nine patches stay ours.
