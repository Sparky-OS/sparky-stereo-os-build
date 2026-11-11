# JPS descriptors in the format writer

The published `kf6-kimageformats 6.30.0-1+stereo3d5+lc1` source, with its complete four-patch series, is the baseline.
This recipe prepares plain `6.30.0-1+stereo3d7`; the normal native Lean Code adapter produces its qualified packages afterward.
It does not modify a published archive.

In a disposable build container, unpack the published descriptor with `dpkg-source -x`, set `SOURCE_DATE_EPOCH` from this recipe's commit timestamp, and run `python3 prepare-source.py SOURCE`.
The script uses `sparky-os/repo/plain-from-lc.py`, retaining a preserve plan beside the source if one exists.
Pass that carried plan to the native adapter’s `lean.debian_prepare --preserve-plan FILE`; this published baseline has no plan.
For this historical source only, it reflows the folded Build-Depends field before the strict helper and restores its formatting afterward.
It keeps the old series and adds `jps-descriptor.patch` and `shared-jpeg-codec.patch`.
Pack the prepared source with `dpkg-source -b SOURCE`, then use the edition's native package adapter.
Qt's Linguist tools compile the ten refusal-message catalogs into the plugin itself.

The patch's `docs/jps.md` describes the metadata fields and cites the complete VRex specification.
The fixed right-first JPEG comment is removed because explicit other layouts would contradict it.
Tests reopen every successful write and independently inspect APP3 fields; unsupported layouts leave device bytes untouched.
Run `kimageformats-jps-writer`, `kimageformats-stereo-metadata` and `kimageformats-stereo`, plus stereo-layer's saved-JPS regression with the new plugin in `QT_PLUGIN_PATH`.

The second patch uses the Qt-free descriptor codec in `libstereo-policy >= 1.17.5` for JPS fields and MPF TIFF directories.
Build the new stereo-layer source package first (it can use the +stereo3d6 plugin), then build this plugin with its new policy development package.
There is no build dependency cycle: the picture library requires plugin +stereo3d6; the +stereo3d7 plugin requires only the policy library.
Its explicit runtime dependency prevents loading it against an older policy library without the new symbols.
The caller uses `Stereo::Picture::saveCorrection` for an existing file, after an accepted save action; applications need no byte writer.
