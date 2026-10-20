# ArtCraft source packaging

This adapter is being qualified for the edition's existing FilmCraft and
PhotoCraft source revisions. A prepared source archive is not a released package.
The normal upstream application checkouts remain authored source.

Export the accepted edition commit into a disposable folder named `filmcraft` or
`photocraft`. Record its full commit and new Debian version in
`SOURCE.edition.json`, with fields `commit` and `version`. Vendor the exact
`Cargo.lock` dependencies with `cargo vendor --locked --versioned-dirs vendor`.
Retain the downloaded crate hashes and check every vendor file before creating
the original-source archive. `prepare.py SOURCE ACCEPTED_MKDEB_RECIPE` creates the
Debian integration; the recipe argument is the reviewed predecessor whose
staging and licence collection are retained. It refuses unexpected recipe text.

The native source pass applies the qualified C/C++ adapter, including eligible
vendored inputs. Rust files remain unchanged: this integration does not provide
a Rust projection adapter. Before Cargo builds offline, `cargo-checksums.py`
checks every vendor checksum and changes only entries bound to that exact
projection report's original and final hashes. It keeps crate identities and
unrelated files unchanged, and records the original checksum manifests for
clean/recovery. Never regenerate arbitrary vendor checksums to silence Cargo.

The build runs the stereo-window and corresponding UI integration tests, stages
through the upstream packaging script, calculates Debian shared-library
dependencies, and applies the separate lc1 payload pass. Native input reduction,
runtime payload reduction and executable size are separate measurements.
Run `python3 test_cargo_checksums.py` for the offline Cargo control: an unbound
source change fails, the qualified transformation builds, restoration is exact,
and an unrelated Rust edit remains an error. Complete application builds and
installed-package checks are required before release.
