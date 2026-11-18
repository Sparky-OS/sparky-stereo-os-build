# Publication input discovery

Read-only inventory before qualifying a publication cohort.
The discovery tools do not execute producers or import cohort modules. Qualification and explicit source-rebuild helpers are separate; none signs or publishes a repository.

```sh
python3 tools/publication-reconcile/inventory.py \
  --build-root /path/to/build-storage --published /path/to/published-tree \
  --output /path/to/evidence
python3 tools/publication-reconcile/reconcile.py \
  /path/to/evidence/inventory.json /path/to/acceptance-rules.json \
  --output /path/to/evidence
python3 tools/publication-reconcile/recipes.py \
  --build . --inventory /path/to/evidence/inventory.json \
  --output /path/to/evidence
python3 tools/publication-reconcile/test_reconcile.py
```

`inventory.py` discovers stage*/out/predecessor/superseded directories through four levels from storage, then inventories package files through four levels relative to each discovered directory.
It retains unreadable paths and reads binary controls and source descriptors.
It records the published indexes' hashes; archive hashes are compared only for staged binaries matching an indexed identity, including Architecture-Variant.
An explicit binary Source version takes precedence over its binary version.

The acceptance-rules input is a private, reviewed JSON list, in first-match order.
Each row has root, source, version, decision and reason; null source/version matches any value under that root.
A candidate rule means the coordinator accepted that generation, not that its build is qualified.
Use specific predecessor exceptions and holds before broader folder rules.
Other predecessor generations remain excluded; discovered generations without a matching rule remain unlisted.
The candidate table includes exact binary filenames, while stage-files.tsv retains every inspected binary and descriptor and its decision.
The published-byte comparison is independent of whether the stage is held or superseded.

`recipes.py` catalogues all tracked roots below sparky-os/packages and sparky-os/upstream, with static producer and version evidence and uninitialized Git source checkouts.
Literal evidence includes historical producers and changelog entries.
It deliberately leaves authoritative-recipe resolution to the reviewer; its output is not an unbuilt-package or build-command list.
A dynamic version, patch-only root or source alias needs source inspection before deciding whether a build is missing.

Before a take list is usable, resolve authoritative recipes, inspect source components and all build receipts, compare payloads against published binaries, and run the release and installed-upgrade checks.
Those checks are separate from discovery.

`metadata.py` verifies the exact selected source closures against descriptors, receipts, clean build records and stage checksums. Its successful `source-artifacts.tsv` is the authority for ancillary selection, not merely a matching source/version in another folder.
`leave-out.py FILES --qualified-artifacts SOURCE_ARTIFACTS --output EVIDENCE` expands excluded components and receipts and names missing inputs. Compare its selected path set independently with the copied pool manifest.
`payload.py FILES INVENTORY --published TREE --output EVIDENCE` keeps every raw listing and tar member difference. Repeat `--explanations REVIEWED.tsv` to attach separately reviewed binary/path/reason records. Directory presentation is normalized; unreadable listing lines refuse the comparison.

`requalify-script.sh` and `rebuild-native.py` consume retained descriptors in a disposable non-root builder and require equality with accepted payload/control members. `generate-metas.sh` needs `META_VERSION`, the selected catalogue, the public archive inputs and the documented builder mounts. Use the supported `KERNEL_META_VERSION_SUFFIX` when the round requires newer kernel meta versions; compare every resulting binary with dpkg.

The `proof/` scripts install a published edition first, verify that its own dpkg is in use, then apply the exact unsigned local `/pool` overlay. They retain complete simulations, installed versions, conffile checks, audit and deep Lean verification. `/base` remains the signed published tree. Run their red/green `test-checks.sh` fixtures before relying on a verdict. Every container needs core dumps disabled and the HTTPS-only APT helper before any apt action.

`budget-run.py --scratch PATH --scratch-gib CAP --root-min-free-gib FLOOR --build-min-free-gib FLOOR --container OWN_NAME --log LOG -- COMMAND` monitors one owned container command and stops that literal name on a budget violation. Supply the lane's actual limits explicitly. It never inspects or stops another container.
