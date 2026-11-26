# ffmpeg-dmo 10:9.1-dmo1+stereo3d18

The edition's FFmpeg on deb-multimedia's 10:9.1-dmo1 (FFmpeg 9.1), queue row 916.
It supersedes +stereo3d16 and +stereo3d17, which were staged for Stereo HandBrake and never published.

## Inputs, named by their sums (`sources.sha256`)

- deb-multimedia's `ffmpeg-dmo_9.1-dmo1.dsc`, through its signed forky index (the orig tarball's signature checks against FFmpeg's release key, FCF9 86EA 15E6 E293 A564 4F10 B432 2F04 D676 58D8, which deb-multimedia ships as `debian/upstream/signing-key.asc`).
- The published `ffmpeg-dmo_9.0.2-dmo1+stereo3d15+lc1.dsc` (round r1123a): its changelog history and its Lean Code preserve plan.

## Make and build

```sh
python3 sparky-os/packages/ffmpeg-dmo/make-source-stereo3d18.py DMO_DSC PUBLISHED15_DSC OUT     # one source, dated by this recipe's commit
bash sparky-os/packages/ffmpeg-dmo/build-stereo3d18.sh IMAGE WORK REPO                       # amd64 and Architecture: all
bash sparky-os/packages/handbrake-dmo/build-twin-i386.sh sparky-os/packages/ffmpeg-dmo IMAGE_I386 DSC WORK_I386 REPO LIBX265_I386_DEBS  # the i386 twin
```

## The series

`patches/series`: deb-multimedia's `01_clean-output.patch` (from its 9.1-dmo1 source), then 116 patches of this folder.
Each patch's header says where it comes from; a patch whose text changed for FFmpeg 9.1 says so in a dated line.

- 76 apply as they did on 9.0.2, byte for byte.
- 20 have their context refreshed; the lines they add and remove are unchanged.
- 20 changed:
  - `02_vf_xfade-3.6.6.patch` (xfade easing, kept; deb-multimedia's 9.1 build drops it), without its slide wrap-around hunks, which FFmpeg 9.1 fixes itself (16a4ce48c);
  - the side data patches 0014, 0028 and 0039 (and the packet ones 0015, 0034, 0040, refreshed), so the values the edition published stay: FFmpeg 9.1's `AV_FRAME_DATA_DOWNMIX_MATRIX`, `AV_FRAME_DATA_GAIN_MAP_PARAMS` and `AV_PKT_DATA_GAIN_MAP_PARAMS` follow the edition's entries;
  - 0035 (FFmpeg 9.1 added its own `auxC` reader; one reader stays, the edition's, with 9.1's gain map and alpha flags), 0042 (an object line FFmpeg 9.1 changed), 0053 (now the edition's commit ca5dbc9 in its original form), 0075 (a test line), 0076 and 0089 (libavutil's minor version from 9.1's 61.19), hb-A05 (a function placed after 9.1's new one), hb-A15 (with FFmpeg 9.1's two pgssubdec fixes).
  - 0015, 0034 and 0040 add FFmpeg 9.1's packet side data handles of their types (the `side_data` bitstream filter names types by them), with the handle test's reference in the edition's numbering; 0037 carries the AuxId lines of 9.1's AVIF alpha grid test.
  - FATE references: 0001 and 0044 take FFmpeg 9.1's ffprobe output (42b8f75a6b, a row without fields; 88f7fd9ec5, program streams only when selected); 0090 and hb-A02 bring the references of 0024 and 0038 to what they print and write (stale since +15 and +16).
- Dropped: `03_fix-padding-in-mp3.patch` (FFmpeg 9.1 has it: 23fccd657c), as deb-multimedia does.
- Upstream already: 0081 is FFmpeg's 96b7f8281a (master, after 9.1), carried with its author's credit.

## Packaging changes against deb-multimedia's

`make-source-stereo3d18.py` applies each exactly once: `libstereo-dibr-dev [amd64]` and `--enable-libstereodibr`; `libfdk-aac-dev` and `libfdk-xhe-aac-dev` only under the `pkg.ffmpeg-dmo.fdk` profile, with `--enable-libfdk-aac --enable-libfdk-xhe-aac --enable-nonfree` (FFmpeg's LICENSE.md calls a GPL build with them unredistributable; `sparky-stereo-ffmpeg-fdk` builds it on the person's machine); `libx265-dev (>= 1:4.3-dmo1+stereo3d2+lc1)`; no `libnvidia-glvkspirv`; the xfade easing header copied again.

## Credits

Christian Marillat (deb-multimedia) for the source package; FFmpeg's authors, among them Romain Beauxis (23fccd657c), Lynne (16a4ce48c), Michael Niedermayer (e3d24a4a1, bfba88103), Ruonan (f3aa9ceb4) and lusoris (96b7f8281a); Raymond Luckhurst (Scriptit UK) for xfade-easing (MIT), as deb-multimedia carries it; HandBrake's authors for the FFmpeg fixes their 1.11.2 carries, each named in its patch (Damiano Galassi, cubicibo and the others); the edition's own patches by Daniel Campos Ramos.
