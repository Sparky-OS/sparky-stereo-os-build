# Bill of materials and build provenance of a publication round

ORDER 394 and 394b. Tools: `make-sbom.py`, `make-provenance.py`, `check-supply-chain.py`, their reader `supply_chain.py`, the round scripts `round-supply-chain.sh` and `sync-supply-chain.sh`, the test `sparky-os/tests/supply-chain/test.sh`.
They live in `sparky-os/release/` beside `verify-online-repository.py` and `publish-tree.sh`'s checks because they read a published tree or a round's cohort, never a recipe's build, and run at the same moment as the release checks.
Everything they write is unsigned; signing and publication are the main session's step of a round.

## Formats

- **Bill of materials: SPDX 2.3, JSON.** SPDX is the international standard ISO/IEC 5962:2021 (spdx.dev, About); 2.3 is the 2.x release the tools read today.
  Measured on 4 November 2026 with the pinned releases: Syft 1.55.0 writes SPDX 2.3 (`-o spdx-json`, default) and 2.2 (`spdx-json@2.2`) and lists no SPDX 3 output; Trivy 0.76.0 reads and writes `spdx` and `spdx-json`; the SPDX project's `spdx-tools` 0.8.5 validates "SPDX-2.2" and "SPDX-2.3".
  SPDX 3.0 was therefore not chosen: none of the readers we want to satisfy takes it.
  Moving to 3.0 later changes the writer only: the reader (`supply_chain.py`) keeps the facts.
- **Provenance: in-toto Statement v1 carrying the SLSA Provenance v1 predicate** (`https://in-toto.io/Statement/v1`, `https://slsa.dev/provenance/v1`).
  One statement per source package version and build architecture; its subjects are every `.deb` that build made.
- **Who did what in our own work** stays CRediT (memory synthetic-user-technique); nothing here replaces it.

## What the bill of materials holds

For every binary package in the repository (or the repository with the cohort laid over it; a cohort package replaces the published one of the same package and architecture):

| SPDX field | Source |
| --- | --- |
| `name`, `versionInfo` | the `.deb` control file |
| `checksums` SHA256 | the `.deb` file, and it must equal the Packages index (the tool stops otherwise) |
| `downloadLocation` | `https://repo.sparkyos.org/` plus the Filename of the Packages index; NOASSERTION for a cohort package not yet published |
| `licenseDeclared` | `debian/copyright` in Debian copyright-format 1.0 (DEP-5): `License:` of each stanza, joined by AND; "and" binds tighter than "or" unless a comma comes before it; a short name with an SPDX identifier is mapped, any other becomes a `LicenseRef-*` with the licence text the copyright file gives. A free-form copyright file gives NOASSERTION and is counted in the report. A copyright file that is a symlink to a sibling's takes the sibling's. |
| `licenseConcluded` | NOASSERTION: nobody concluded anything |
| `originator` | Debian, deb-multimedia or SparkyLinux, from `Original-Maintainer` and the version; the basis is in the package `comment` |
| `supplier` | Sparky Stereo OS |
| annotation `sparky:lean-code` | the Lean Code record `/usr/share/dpkg-stereo/lc/<package>/<arch>.json`: format, scope, renderer identity and hash, file counts by status, the hr companion package, the record's sha256, and a digest over every projected file's authored (hr) and projected hashes |
| `externalRefs` purl | `pkg:deb/sparky-stereo-os/NAME@VERSION?arch=ARCH&distro=mashtabba` |
| `GENERATED_FROM` | the source package (name, version, the `.dsc`'s sha256, and the sha256 of every file its Checksums-Sha256 lists) |

A package with no `Original-Maintainer` and no origin sibling is origin `edition` (its own source or upstream's: the metadata does not say which).
Contacts (e-mail addresses) are never copied into the document.
The document's namespace is made from the package hashes, so the same inputs give the same document.

## Build type and builder

`https://github.com/Sparky-OS/sparky-stereo-os-build/blob/main/sparky-os/release/SUPPLY-CHAIN.md#build-type-debian-source-lean-code-v1`

- **Build type `debian-source-lean-code-v1`.** The inputs are a Debian source package (`.dsc` and the files it lists) and the build repository's recipe for it; the build runs `dpkg-buildpackage` inside a container with the build dependencies installed from the repository and Debian; Lean Code projects the payload before the checksums are made (`lean.debhelper`), and `release check-debs` gates the result.
- `externalParameters`: the source (name, version), the architecture, the recipe path in the build repository.
- `internalParameters`: the Lean Code summary (renderers, their hashes, file counts, hr companion packages) and, when a `.buildinfo` exists, its Environment, Build-Origin and Build-Architecture.
- `resolvedDependencies`: the `.dsc` and its files with sha256, and, with a `.buildinfo`, every Installed-Build-Depends entry as a purl (`pkg:deb/<Build-Origin>/NAME@VERSION`; a `.buildinfo` has no hash for them).
- `runDetails.builder.id`: `...#builder-lane-container`, the partner lane's container build driven by the recipe's `build-in-container.sh`, run by a lane and accepted and staged by the main session.
  This platform is not hardened: the statements describe the build, they do not prove it.
  They meet the content requirements of SLSA Build L1 (provenance exists, lists the builder, the build type and the external parameters); they are unsigned, so not L2.
- `byproducts`: the `.buildinfo` file when one exists.
- `finishedOn`: the `.buildinfo` Build-Date (RFC 2822, converted to UTC).

## The build record (ORDER 394b)

Every Lean Code build leaves `SOURCE_VERSION_ARCH.sparky-build.json` next to its `.deb` files (format `sparky-build-record/1`).
Two points of the Lean Code toolkit write it, because every package build passes both:

- `lean.debhelper` replaces `dh_builddeb`, so no `.deb` of a build is made without it.
  It notes when `dpkg-buildpackage` started (read from `/proc`, in whole seconds, so up to a second early) in `.sparky-build-start.json`.
- `lean.release check-debs` is the gate every build script ends with.
  After the checks pass it writes the record, with the `.deb` files' sha256, the name and sha256 of the `.buildinfo`, `.changes` and `.dsc` files beside them, and the finish time (the moment the gate accepted the packages).
  `--no-record` only checks, for the controls that run the gate on published or read-only files.

The build repository's commit, the builder image's id, the invocation id and the moment the script started are known only to the host.
`sparky-os/repo/build-provenance.sh` reads them (`git rev-parse HEAD` and whether `sparky-os` differs from it, `docker image inspect`, a random UUID, the clock) and `sparky_provenance_init IMAGE` fills `"${SPARKY_PROV_ARGS[@]}"`, which the build script adds to its `docker run` line as `SPARKY_BUILD_*` variables.
A fact that was not passed is not guessed: the record lists it under `unrecorded`, the gate prints it, and the statement keeps the gap.
`SPARKY_PROVENANCE_REQUIRED=1` stops the build script, and the gate, instead.
The reader refuses a record in which a fact is neither recorded nor listed as unrecorded.

A build that never called `sparky_provenance_init` is a stated failure (ORDER 412): `lean.release check-debs` finds none of `SPARKY_BUILD_INVOCATION` and `SPARKY_BUILD_STARTED` (the init call always passes both) and stops with `lc1: release blocked: the build script did not call sparky_provenance_init ...`, writing no record.
A recipe that cannot have host facts sets `SPARKY_PROVENANCE_OPTOUT="<reason>"` in the container; the record then carries `provenanceOptOut`, still lists the four facts under `unrecorded`, and the statement copies the reason into `internalParameters.buildRecord`.
An empty reason, or an opt-out beside the init call, stops too.
Facts that were asked for and could not be read (no git checkout, no image id) keep the earlier path: said on stderr, listed as unrecorded, `SPARKY_PROVENANCE_REQUIRED=1` stops.

Build scripts wired (they call `sparky_provenance_init`): the `build.sh` of catalogue-rebuilds, command-not-found, dpkg, full-sbs, kscreen, kscreenlocker, kwin, libkscreen, librsvg (amd64 and i386), mesa, pipewire-bluez5-codec-aac, plasma-desktop, plasma-union, plasma-wayland-protocols, plasma-workspace, qt6-3d, qt6-base, qt6-declarative, qt6-svg, stereo-declare, sview, transition-rebuilds and vibe, `packages/hardware-decode/packaging/run-build.sh`, `upstream/vlc/vlc-stereo-packaging/build-lc.sh`, and `release/build-dh-lean.sh`.
The Python drivers `release/run-native-batch.py`, `run-i386-batch.py`, `run-prepared-source.py`, `run-browser-native.py` and `check-source-rebuild.py` add `*provenance_args(IMAGE)` (release/provenance_args.py, which runs the same shell function) to their `docker run` command.
The recipes that run inside a container somebody starts by hand (kf6-kio, kf6-networkmanager-qt, kpmcore, nvidia-legacy-580xx-userspace, pkcs11-proxy, plasma-discover, plasma-nm, snmptt, spatial-video-rebuilds, xfsprogs, xwayland, zfs-linux, dmemcg-booster and the like) have no host driver in the repository: whoever starts the container passes `"${SPARKY_PROV_ARGS[@]}"` (source `build-provenance.sh`, call the init) or sets `SPARKY_PROVENANCE_OPTOUT`, or `check-debs` stops with the message above.
Wiring one is two lines: source `build-provenance.sh` after `HERE=`, call `sparky_provenance_init IMAGE` before `docker run`, and put `"${SPARKY_PROV_ARGS[@]}"` on that line.
`tests/supply-chain/test-wiring.sh` fails on a host driver (a `docker run` in packages, release or upstream) whose container reaches the gate without the call, the helper or the opt-out.
Plain builds that never reach the Lean Code gate (`repo/build-from-dsc.sh`) write no record.

`make-provenance.py --build-dir DIR` (also the older `--buildinfo-dir`) searches the folders for records and `.buildinfo` files.
A record changes the statement:

| statement field | record field |
| --- | --- |
| `resolvedDependencies` entry `recipe-repository`: `uri` the build repository, `digest.gitCommit`, annotation `worktreeDiffersFromCommit` | `recipeCommit`, `recipeDirty` |
| `runDetails.builder.builderDependencies`: the image, `digest.sha256` | `builderImage`, `builderImageName`, `builderImageRepoDigests` |
| `runDetails.metadata.invocationId`, `startedOn`, `finishedOn` | `invocationId`, `startedOn`, `finishedOn` |
| `internalParameters.buildRecord` | `startBasis` (`build-script` or `dpkg-buildpackage`), `unrecorded`, `buildArchitecture` |
| `byproducts` | the record file |

`check-supply-chain.py provenance DIR --require-recorded [--only-source NAME]` makes those facts mandatory: a statement without them is a problem.
A round does not use it yet, because the packages built before 394b have no record.

## Gaps (written per recipe by `make-provenance.py --report`)

A fact nothing records is not stated; the gap report names it per recipe.
Builds made after 394b through a wired script close the first four; the others keep them.

| gap | what is missing | how to close it |
| --- | --- | --- |
| `recipe-commit`, `builder-image-digest`, `build-start-time`, `invocation-id` | no build record, or the record lists them as unrecorded | wire the build script (above) |
| `build-environment`, `build-dependencies` | no `.buildinfo` | keep the `.buildinfo` that `dpkg-buildpackage` writes beside the `.deb` files: the record names it, and the stage folder must copy it |
| `build-finish-time` | neither a `.buildinfo` nor a record | as above |
| `recipe-unresolved` | no recipe folder with the source's name or changelog | register the source with its recipe |
| `source-dsc-missing` | the `.dsc` was not beside the tree or the cohort | keep the `.dsc` in the stage folder |

## Validation

`check-supply-chain.py` uses the standards' own libraries: the SPDX project's `spdx-tools` (tools-python) for the document, in-toto's `in-toto-attestation` library (Statement v1 and the generated SLSA Provenance v1 protobuf, unknown fields refused) for the statements.
`sparky-os/tests/supply-chain/test.sh` runs them on a small fixture repository, red on deliberately broken copies and green on the real ones.

## A round

The tools run in a container whose image is built from `release/supply-chain-image`:

- `Dockerfile`: an amd64 Debian testing base (pass `--build-arg BASE=` an image pulled by digest) with `python3`, `python3-venv`, `dpkg-dev`, `xz-utils` and `ca-certificates`; no `git` (the tools read files) and no `jsonschema` (nothing imports it).
- `requirements.txt`: the Python packages, each pinned with its sha256 and installed by `pip install --require-hashes --no-deps`.
  `make-requirements.py top-level.txt requirements.txt` writes it (run inside the base, with network): it resolves the pinned top-level packages in a throwaway environment, downloads each package once, takes the sha256 of the bytes it got and compares it with the hash PyPI declares for that file name (`https://pypi.org/pypi/NAME/VERSION/json`, `urls[].digests.sha256`); it stops unless both agree.
  PyPI's index is the only source of those hashes, so a hash proves the bytes did not change after this was written, not who uploaded them.
- Current set (4 November 2026): spdx-tools 0.8.5, in-toto-attestation 0.9.3, license-expression 30.4.4, protobuf 7.36.2 and their dependencies beartype, boolean.py, click, ply, pyparsing, PyYAML, rdflib, semantic-version, uritools and xmltodict.

**Part 1, in `official-part1.sh`, after `publish-tree.sh` returns 0 and `sync`** (unsigned, nothing sent):

`round-supply-chain.sh DEST ROUND OUT STAGEDIRS` runs `round-supply-chain-inner.sh` in the container (network off, DEST and the stage folders read only):
`make-sbom.py` on DEST, `check-supply-chain.py sbom --tree DEST`, `make-provenance.py` with a `--build-dir` for every line of `stagedirs.txt`, `check-supply-chain.py provenance --tree DEST`, then `sha256sum` of the SPDX document, the provenance bundle and the gap report into `OUT/publish/SHA256SUMS`.
Any non-zero exit stops Part 1.

**Part 2, signed by the main session with the official key** (the same key and call as `publish-tree.sh`'s Release signature):

`gpg --homedir $SPARKY_REPO_GNUPG --local-user 10DFD38DAD1E4808BC688E5A945E5D079A2A0B9C --armor --detach-sign` on `OUT/publish/SHA256SUMS`, writing `SHA256SUMS.asc` beside it.
This is the key apt clients already trust, so a person verifies with `gpgv` and the repository key they have.
A later step may wrap each statement in a DSSE envelope signed with the same key; the statements need no change.

**Publication, after the repository itself is live** (the documents describe it):

`sync-supply-chain.sh OUT/publish ROUND sparky-stereo-repo.asc` is a dry run; with `--go` it checks `SHA256SUMS` against the files and `SHA256SUMS.asc` against the repository key (it refuses unsigned documents), then sends the files to `sbom/ROUND/` (SHA256SUMS and its signature last) and points the symlink `sbom/latest` at it.
It owns only `sbom/ROUND/` and `sbom/latest`: `sync-to-server.sh` owns only `pool/` and `dists/`, and neither deletes what the other sends.
`verify-online-repository.py DEST --supply-chain-dir OUT/publish --supply-chain-round ROUND` then checks that every served file under `sbom/ROUND/` and `sbom/latest/` is the signed local file and that the signature verifies.

What the documents give a person: `grep` of the SPDX file for a package gives its version, hash, origin, licence and source; the provenance line for the same `.deb` hash says what built it and what is not known.

## Tests

`sparky-os/tests/supply-chain/test.sh WORKDIR` (inside the image: documents, statements, build records, the validators red and green) and `test-publish.sh WORKDIR` (on a host with rsync and gpg, throwaway key: sync-supply-chain.sh and the served-files check).
`sparky-os/lean/tests/test_buildrecord.py` tests the writer.
