# Kdenlive and MLT for ORDER 61e

Kdenlive 26.08.1-1+stereo3d10+lc1 and MLT 7.40.0-1+stereo3d9+lc1, made from the published +lc1 sources of round r1118a
(kdenlive +stereo3d6, mlt +stereo3d6), never from a work tree. The staged Kdenlive +stereo3d8 and +stereo3d9 and MLT +stereo3d7
and +stereo3d8 of ORDER 61e's first two milestones enter no round: these sources carry all of it (ORDER 61e, three milestones,
the third as 61f). Both build against the stereo layer 1.23.2 the round carries (`layer-1.23.2.sha256`; `build.sh WORK REPO IMAGE
LAYER`, LAYER a folder holding those packages), installed as staged siblings before the build dependencies.

| Package | What this recipe adds |
|---|---|
| MLT +stereo3d9 | 0013: `stereo3d_unpack` as the first filter of a producer (`in_producer`, `target_views`); 0014: the HEVC frame packing SEI through FFmpeg's `hevc_metadata`; 0015: a deep source keeps its bits (RGBA64, the asked format handed back, no alpha mask on an opaque picture); 0016: half or whole views judged by the producer's own frame; 0017: a 2D picture in both eyes (`packing=mono`); 0018: a 3D still read as its pair through the stereo layer (Build-Depends libstereo-layer-dev 1.23.2) |
| Kdenlive +stereo3d9 | 0009 (edition only): 3D preview by default; 0010: told once when 3D cannot be shown; 0011: the Stereoscopic 3D render presets; 0012: each 3D clip taken apart side by side in a 3D project; 0013: thumbnails from the left eye, a packing only the SEI says learned from a frame; 0014: a 3D project's resolution is one eye's in its renders; 0015: each clip's 3D input corrections in its properties, and the save into the file; 0016: the monitors' 3D options are the layer's Enable 3D and Display Settings, the project's Right Eye First moved to its clips; 0017: an unknown preset name stops a command-line render; 0018: both monitors in 3D at once; 0019: a 2D element in both eyes, and the monitors at one eye's full resolution; 0020: the 3D Input Format list from the installed layer; 0021: 3D stills in the clip's properties, and the monitor after a save; 0022: a 3D render keeps the source's depth or says it writes fewer bits, and a 3D FFV1 preset; then `translations/kdenlive-order46c-catalogues.patch` (ORDER 46c), `translations/kdenlive-order61e.po.patch` (ORDER 61e in ten languages, ORDER 46e) and `translations/kdenlive-order61f.po.patch` |

Kdenlive's `Depends` is raised from `libmlt7 (>= 7.40.0-1+stereo3d5+lc1)` to `libmlt7 (>= 7.40.0-1+stereo3d9+lc1), kscreen, libkf6kcmutils-bin`: patch 0012 needs MLT's `in_producer`, a deep 3D clip MLT 0015, a 2D element in a 3D project MLT 0017; the Display Settings shortcut opens kscreen's Display Configuration page through `kcmshell6` (a designed feature's dependency is a Depends). Its Build-Depends name `libstereo-layer-dev (>= 1.23.2)`, for the layer's input list.

## Where the published patches live

The published `debian.tar.xz` is the truth; a folder of the build tree is not proof of what ships.

| Published patch of kdenlive +stereo3d6 | Recorded in |
|---|---|
| 0001 to 0005 | `sparky-os/upstream/kdenlive/kdenlive/` (the SEI wave of 2026-10-06; its `build.sh` made +stereo3d2) |
| 0006 (+stereo3d3, 2026-10-15) | only in the published source |
| 0007 | `sparky-os/packages/full-sbs/patches/kdenlive/` (+stereo3d4) |
| 0008 | `sparky-os/packages/hardware-decode/patches/kdenlive/` (+stereo3d5) |
| +stereo3d6 | `sparky-os/packages/transition-rebuilds/entries/kdenlive_26.08.1-1+stereo3d6.txt` (the same source, rebuilt for libkddockwidgets-qt6-4) |

MLT +stereo3d6's 0001 to 0006 are in `sparky-os/upstream/kdenlive/mlt/`, 0007 and 0008 only in the published source, 0009 in `full-sbs`, 0010 to 0012 in `hardware-decode`, and +stereo3d6 itself is `sparky-os/packages/mlt-bindings/`.

## Build

```sh
export DOCKER_HOST=...   SPARKY_LC_ARCHIVE_DIR=/path/to/archive   SPARKY_CONTAINER_PREFIX=lane-prefix
bash sparky-os/packages/kdenlive-stereo-61e/build.sh WORK /path/to/published-tree BUILD_IMAGE
```

`make-sources.sh` packs both sources with `repo/lc-successor.py --in-place --overlay --reapply-patches` (the whole new series is applied before packing), dated by this folder's last commit; `build.sh` builds MLT, then Kdenlive with the new MLT as the link gate's edition sibling (`release/build-from-lc-dsc.sh`, `SPARKY_LC_SIBLINGS_DIR`).
The published builds of +stereo3d6 are copied into `previous-*` for the gate's comparison, but for libmlt-perl: the published one depends on `perlapi-5.42.3`, which Debian testing no longer has (perl 5.44.0-3 on 2026-11-21), so it cannot be installed and cannot be the gate's baseline; the one built here links today's perl.
