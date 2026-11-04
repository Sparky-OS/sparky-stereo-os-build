# Bill of materials and build provenance of a publication round

ORDER 394. Tools: `make-sbom.py`, `make-provenance.py`, `check-supply-chain.py`, their reader `supply_chain.py`, the test `sparky-os/tests/supply-chain/test.sh`.
They live in `sparky-os/release/` beside `verify-online-repository.py` and `publish-tree.sh`'s checks because they read a published tree or a round's cohort, never a recipe's build, and run at the same moment as the release checks.
Everything they write is unsigned; signing and publication are the main session's step of a round.

## Formats

- **Bill of materials: SPDX 2.3, JSON** (ISO/IEC 5962:2021 is SPDX 2.2.1; 2.3 is the current 2.x release of the same data model).
  SPDX 3.0 was not chosen: Syft, Trivy, the SPDX project's own Python validator and Siemens' debsbom (the Debian-specific generator) read and write 2.3 today, and the SPDX 3.0 profile for Debian sources has no consumer among them.
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

## Gaps (written per recipe by `make-provenance.py --report`)

Nothing records these today, so no statement states them:

| gap | what is missing | how to close it |
| --- | --- | --- |
| `recipe-commit` | the build repository's commit the build ran from | the build script writes `git rev-parse HEAD` of the build repository into a file next to the `.deb` files (a `.buildinfo` Environment line or a `provenance.json`) |
| `builder-image-digest` | the container image digest the build ran in (SLSA `builderDependencies`) | the build script records `docker inspect --format '{{.Image}}'` and the image's repo digest |
| `build-environment`, `build-dependencies`, `build-finish-time` | with no `.buildinfo`, the installed build dependencies, the environment and the time | keep the `.buildinfo` that `dpkg-buildpackage` writes (18 of the 39 stage folders of the 4 November cohort have one; the publication tree copies none) |
| `build-start-time`, `invocation-id` | no build records them | the build script writes both |
| `recipe-unresolved` | no recipe folder with the source's name or changelog | register the source with its recipe |
| `source-dsc-missing` | the `.dsc` was not beside the tree or the cohort | keep the `.dsc` in the stage folder |

## Validation

`check-supply-chain.py` uses the standards' own libraries: the SPDX project's `spdx-tools` (tools-python) for the document, in-toto's `in-toto-attestation` library (Statement v1 and the generated SLSA Provenance v1 protobuf, unknown fields refused) for the statements.
`sparky-os/tests/supply-chain/test.sh` runs them on a small fixture repository, red on deliberately broken copies and green on the real ones.

## A round

See the round plan in the lane report; in short: Part 1 runs `make-sbom.py` and `make-provenance.py` after `publish-tree.sh` on DEST, checks them with `check-supply-chain.py`, and Part 2 signs the documents with the official key and publishes them under `sbom/<round>/` beside the repository.
