# JPS descriptors in the format writer

The published `kf6-kimageformats 6.30.0-1+stereo3d5+lc1` source, with its complete four-patch series, is the baseline.
This recipe prepares plain `6.30.0-1+stereo3d6`; the normal native Lean Code adapter produces its qualified packages afterward.
It does not modify a published archive.

In a disposable build container, unpack the published descriptor with `dpkg-source -x`, set `SOURCE_DATE_EPOCH` from this recipe's commit timestamp, and run `python3 prepare-source.py SOURCE`.
The script uses `sparky-os/repo/plain-from-lc.py`, retaining a preserve plan beside the source if one exists.
For this historical source only, it reflows the folded Build-Depends field before the strict helper and restores its formatting afterward.
It keeps the old series and adds `jps-descriptor.patch`.
Pack the prepared source with `dpkg-source -b SOURCE`, then use the edition's native package adapter.
Qt's Linguist tools compile the ten refusal-message catalogs into the plugin itself.

The patch's `docs/jps.md` describes the metadata fields and cites the complete VRex specification.
The fixed right-first JPEG comment is removed because explicit other layouts would contradict it.
Tests reopen every successful write and independently inspect APP3 fields; unsupported layouts leave device bytes untouched.
Run `kimageformats-jps-writer`, `kimageformats-stereo-metadata` and `kimageformats-stereo`, plus stereo-layer's saved-JPS regression with the new plugin in `QT_PLUGIN_PATH`.
