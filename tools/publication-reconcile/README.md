# Publication input discovery

Read-only inventory before qualifying a publication cohort.
The tools never execute producers, import cohort modules, copy packages or publish anything.

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
