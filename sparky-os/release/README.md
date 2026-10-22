# Release engineering: Lean Code migration, repository qualification and machine uplift

These tools rebuild the edition's packages with Lean Code (`sparky-os/lean`, `LEAN-CODE-POLICY.md`), qualify every candidate in throwaway containers, assemble and sign the repository, check the published copy against the qualified one, and move a machine onto it.
They were first used for the migration of 20 October 2026, when the whole development repository moved to `+lc1` packages and both test machines upgraded to it.
The kernel's own build and qualification steps are in `kernel/qualification`.

Nothing here publishes on its own: candidates stay outside the repository until they are reviewed, `assemble-final-repository.py` builds a local signed tree, and `sparky-os/repo/sync-to-server.sh` sends it only with `--go`.

## Settings

Every path, host and key comes from the local configuration: copy `sparky-os/config/build.conf.example` to `~/.config/sparky-stereo/build.conf` (or set `SPARKY_STEREO_CONFIG`) and fill it in.
A tool stops with the name of any key it needs and does not find.
The run's own record (`SPARKY_RUN_RECORD`) holds the inventories the tools read (`source-migration-inventory.json` and its overrides, `current-packages.json`, `migration-progress.json`) and the checkpoints and evidence they write; keep it outside this tree.

Builds share four container slots (`build_slots.py`) and refuse a cached image of the wrong CPU (`image_platform.py`).

## Native source migration

| Tool | What it does |
|---|---|
| `register-source.py` | Registers a checksum-verified source descriptor against the starting inventory. |
| `run-native-batch.py` | Builds the named sources from the inventory with Lean Code, each in its own container. |
| `run-prepared-source.py` | Builds one prepared `lc1` source descriptor. |
| `run-i386-batch.py` | Builds another architecture from the exact prepared amd64 source. |
| `verify-multiarch.py` | Compares the shared files of a Multi-Arch: same pair. |
| `check-source-rebuild.py` | Rebuilds a script or tool source and compares the installed archive surfaces. |
| `collect-compiler-inputs.py`, `refresh-compiler-input-summary.py` | Intersect the compiler's real dependency files with the projection proof. |
| `measure-payload-savings.py` | Measures payload projection apart from source projection and cache removal. |
| `checkpoint.py`, `show-build-status.py` | Record coverage; read bounded log tails while builds run. |
| `prune-completed-build.py` | Removes a successful build tree after its evidence is retained. |
| `fetch-wine-build-inputs.py` | Retains the exact Wine 10 build inputs from Debian's authenticated index. |
| `check-stereo-create-fixture.sh` | Runs the stereo-create fixture inside the migration container. |
| `blender-installed-check.py` | Exercises packaged Blender's node registry and stereo CPU renderer. |

## Browser package (Waterfox Stereo)

| Tool | What it does |
|---|---|
| `browser-source-preflight.py` | Read-only checks of the browser inputs, collecting every failure. |
| `check-accepted-browser-toolchains.py` | Compares the upstream compiler archives with the accepted ones. |
| `run-browser-native.py` | Builds the browser with its pinned compiler bundle. |
| `qualify-browser-package.py`, `browser_fixtures.py` | Install the candidate in isolation and replay the browser cases. |
| `prune-qualified-browser.py` | Keeps the proofs and removes the qualified build tree. |

## Repository

| Tool | What it does |
|---|---|
| `audit-candidate-sources.py`, `audit-source-archive-bytes.py` | Check source coverage and every source archive of the staged candidates. |
| `check-repository-dependencies.py` | Early resolver check of the candidate set. |
| `refresh-final-metadata.py` | Builds the final meta-packages and apt configuration. |
| `stage-final-repository.py` | Selects the immutable release inputs once qualification passed. |
| `assemble-final-repository.py` | Assembles and signs the local tree (`sparky-os/repo/publish-tree.sh`). |
| `check-final-installed.py` | Exercises the signed candidate repository in a fresh Debian container. |
| `verify-online-repository.py` | Checks the published tree against the qualified local copy. |

## Machine uplift

| Tool | What it does |
|---|---|
| `check-host-upgrade.py` | Simulates a machine's upgrade against the signed candidate. |
| `capture-a10-upgrade-state.py`, `capture-a10-uptime.py` | Copy the test laptop's package and boot metadata over ssh, read-only. |
| `prepare-shader-bundles.py`, `seed-shader-recovery.py`, `check-shader-migration.py` | Keep exact original shaders recoverable through the dpkg-stereo upgrade. |
| `machine-upgrade-phase.py` | Runs one reviewed upgrade phase that removes nothing; never reboots. |
| `switch-to-online-source.py` | Points apt at the verified online repository, keeping other sources and pins. |
| `verify-machine-uplift.py` | Read-only installed-package and boot audit after the upgrade. |
| `inspect-monitoring-history.py` | Reads local monitoring history around the upgrade. |
