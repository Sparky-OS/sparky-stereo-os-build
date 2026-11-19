# HandBrake stereo successor

The source baseline is deb-multimedia's `handbrake-dmo` 1:1.11.2-dmo3.
Keep its three binary package names and bundled media-library route.
The initial patches carry Damiano Galassi's upstream stereo metadata preservation and Daniel Ramos's upstream x264 frame-packing commit, with DEP-3 attribution in each patch.

`prepare-source.py SOURCE` accepts a fresh extraction of that descriptor, applies the recipe's patches and prepares the source through the edition's Lean Code adapter.
The recipe must be committed before preparation, because its source date and build record come from the commit.
GTK sources retain translator comments through message extraction and resource generation.
The installed-package marked-source matrix and package comparison qualify the resulting binaries separately.
