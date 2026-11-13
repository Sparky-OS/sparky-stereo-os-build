# craft-suite: the Craft apps as Debian packages with shared libraries

One source package for Storytold's Craft suite at the edition's stereo branches: every app a package of its own, the crates the apps share in one Rust dynamic library, each app's own crates in one library inside its package.
It is built by the edition's own rustc (the `rustc` recipe beside this one) from vendored crates, with no network, through Lean Code.
Today it builds PhotoCraft, LightCraft and FilmCraft; `suite.json` says why TextureCraft and AniCraft wait.

## The files

- `suite.json`: every pin (app revisions, versions, programs, features, sibling library revisions, fonts, catalogues), the compiler, what is built, what is held and what is not packaged.
- `fetch.sh OUT`: the only step with the network. It needs `FETCH_IMAGE`, an image with the edition's cargo.
- `build.sh WORK SOURCES SEED_DIR [all|deps|build|source]`: the sources, the build without network, `check-debs`. It needs `BASE_IMAGE`, a Debian testing amd64 image by digest; `SEED_DIR` holds the edition's rustc, cargo and libstd packages.
- `suite-source.py`: sibling paths to pinned git dependencies, per-source vendor folders, the cargo configuration.
- `suite-tree.py`, `suite-trees.sh`, `suite-generate.sh`: the one workspace and the libraries' crates; `suite-fixups.json`: the lines one resolve needs changed in the generated copy.
- `suite-build.sh`: one resolve for every program; `suite-debian.py`: control, changelog, copyright, the version choices file.
- `debian/`: the rules, staging through each app's own packaging script, the launcher, the name check, the checksum binding.
- `smoke.tsv`: the programs `lean.release check-link --smoke` starts.

## Run it

```sh
FETCH_IMAGE=IMAGE_WITH_OUR_CARGO ./fetch.sh /scratch/craft-sources
BASE_IMAGE=debian@sha256:... ./build.sh /scratch/craft-build /scratch/craft-sources /scratch/rustc-1.99.1/out
PYTHONPATH=../.. python3 -m lean.release check-link --archive-config ../../lean/archive.example.json --scratch /scratch/link \
    --siblings-file SIBLINGS --smoke smoke.tsv /scratch/craft-build/out/*+lc1_*.deb
```

`SIBLINGS` names the compiler's `libstd-rust-HASH` archive.
The candidates and their `SHA256SUMS` land in `WORK/out`.
A compiler other than the one `suite.json` names stops the build; so does a library name that differs from the source's.
The skill page [a Rust suite as shared libraries](https://github.com/Sparky-OS/sparky-stereo-os/blob/main/skills/edition-packaging/references/rust-suite-shared-libraries.md) has the recipe's reasons, numbers and traps.

## What the package does to the apps

Nothing in the apps' sources is changed; the generated workspace is a copy.
Two lines differ in that copy (`suite-fixups.json`), both the same signature that one resolve's feature set requires.
The launcher names a version choices file, so an app's own update check offers nothing and asks no server: apt updates the packages.
