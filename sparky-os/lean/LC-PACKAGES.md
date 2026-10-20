# lc1 implementation and migration

**Main principle: [prepare ahead of consumption](../LEAN-CODE-POLICY.md#main-principle-prepare-ahead-of-consumption).** Keep the complete source for people and prepare the verified machine form upstream, reducing repeated reading, scanning and parsing in the consuming build or runtime path.

Daniel authorized build-time Lean Code for all packages and ISOs we publish, with an **lc** marker for clients, on 2026-10-18. The public contract is in the edition documentation, `docs/lean-code-packages.md`.

## Commands

From `sparky-os` (or set `PYTHONPATH` to that directory):

```sh
# Finish provenance before projection. STAGING is a disposable package tree.
repo/provenance.sh --tree STAGING
python3 -m lean.release build-tree STAGING OUTPUT

# Runtime archives AND their matching HR companions, before signing:
python3 -m lean.release check-debs OUTPUT/*.deb
python3 -m lean.release check-repo PUBLISHED_TREE

# Before an ISO upload:
python3 -m lean.release check-iso IMAGE.iso

# Local checks, no host package installation:
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s lean/tests -v
```

`build-tree` replaces the final `dpkg-deb` call. It never repacks an upstream archive, changes a version implicitly or overwrites an existing output. Its input is disposable: after any failed projection, rebuild staging from HR before retrying. Run it before generating `.changes`, `.buildinfo` checksums or signatures. The existing provenance helper now accepts staging trees and refuses to alter sealed packages.

The shared marker/manifest code is `package.py`; release commands are `release.py`. `dpkg-stereo` 0.1.7 reads this metadata, skips the renderer, verifies build-time files, fetches exact HR documentation and resolves locations. Build records are separate from local `records/` and `conffiles.tsv`. APT authenticates the archive normally; the marker is evidence of processing, not authentication. Older clients are excluded with `Breaks: dpkg-stereo (<< 0.1.6)` when dpkg-stereo is installed; the runtime packages remain installable on systems without it.

The package builder for dpkg-stereo is the first integration. `repo/publish-tree.sh` verifies the complete selection before modifying the pool or signing; `repo/sync-to-server.sh` verifies the final pool before rsync. The unsigned development index stays usable while packages are migrated. All public binary packages, including carried packages, must have a valid marker and their exact HR companions. A carried upstream archive must be rebuilt as a versioned edition package before publication under this rule; it is never silently rewritten under upstream's version.

The ISO entry point defaults to `LEAN=1`. `LEAN=0` needs `ISO_PURPOSE=benchmark` and a `-nolean-` name. The pre-squashfs hook now runs `--verify`, writes `lc-image.json`, and the packer seals the final ISO with a hash-bound `.lc1.json` attestation. Run `check-iso` before manual uploads as well; it checks evidence and hashes, not bootability. General remastering remains optional.

## Coverage and unfinished integration

The marker scope is `qualified-installed-payload`. Every regular payload file or link appears in the manifest, including unchanged files and unqualified formats with reasons. A failed consumer equivalence check blocks marking. Binary bytes are not rewritten. Maintainer scripts and other `DEBIAN/` metadata are not runtime payload projections. Native pre-compilation source processing is a separate requirement and is not certified by `lc1`.

Existing published versions are untouched. Remaining migration work: replace the final assembly step in the other package builders and native Debian packaging rules; rebuild selected packages at new versions with matching source and HR artifacts; carry the new client; rebuild and boot/install-test the ISO; measure client update costs and cold/warm starts on the A10. Publishing old unmarked packages with the updated scripts is intentionally blocked until that migration is complete. The 19 October development channel applies this to the Android companion packages and maintainer tooling. The final ISO and remaining repository are separate migration work.

External updater adapters (Discord's self-updated payload, npm helpers, vendor installers, Flatpak/Snap and container images) remain separate work. The workstation audit is in the private research folder `lean-code-external-2026-10-18`; it performed in-memory checks, not installed-file changes.

## Native and JVM development build adapters (19 October)

`source_tree.py` projects disposable native inputs before configuration and retains authored hashes/copies plus mtimes. `debhelper.py` restores installed headers from that exact source before the payload pass and registers ordinary, HR and automatic debug archives before `.changes`/`.buildinfo` checksums. Native `.dsc` inputs stay authored. KPipeWire 6.7.4-1+stereo3d7 and KRdp 6.7.4-1+stereo3d8 exercise this path.

Java and Kotlin adapters use real compiler lexers (qualified Android build: JDK 17, Kotlin 2.4.0). The compiler classpath is needed only where source is projected/resolved, not by ordinary binary clients. Flat Headset publishes its pre-compilation wrapper, per-component evidence and source resolver in its Android source tree. Its generator-read FreeRDP header remains authored. The `lc1` marker does not certify these separate pre-compilation checks.
