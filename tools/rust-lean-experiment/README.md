# Preparing Rust compiler sources for a Lean Code comparison

These tools prepare three source forms and an offline measurement kit for rustc 1.99.1+dfsg1.
Source projection and kit qualification happen before the measurement machine runs the fixed experiment.
The hand-back records which checks actually passed; hardware results exist only after the bench run.

Use an extracted Debian source with its patch series applied, the edition's Lean toolkit 0.1.29 on `PYTHONPATH`, and the edition's rustc 1.99.1 installed in an isolated container.
The 1.99.1 compiler checks lexical equivalence; the eventual toolchain builds use the same pinned 1.98.1 seed for every form.
Set `LC_ALL=C` and disable core dumps in that container.

```sh
python3 tools/rust-lean-experiment/test_prepare.py
python3 tools/rust-lean-experiment/prepare.py AUTHORED OUTPUT
python3 tools/rust-lean-experiment/verify.py AUTHORED OUTPUT
```

For Debian's pinned 1.99.1+dfsg1-1~exp1 source, add `--checksum-baseline tools/rust-lean-experiment/debian-1.99.1-checksum-baseline.json` to the preparation command.
Its ten existing Cargo/Rust checksum discrepancies come from Debian's applied patches.
The exception file binds the complete authored tree and each old checksum to an applied quilt backup; another tree or an unreviewed changed hash is refused.
These are provenance metadata reconciliations, counted separately from source savings.

Expect the tests to pass, preparation to print its progress, and verification to print the three census rows and `PASS: complete file/mode/link manifests, ledger and preservation checks`.
`OUTPUT` must not exist before preparation.
An interrupted preparation has no accepted `source-report.json`; inspect the partial output before explicitly retiring it and starting again.
Preparation checks free space before copying and between batches, reserving the configured scratch floor plus 5 GiB.
The unattended runner supplies a separate continuously sampled guard.

The authored tree is read and checked again at the end.
Form B uses the unchanged Rust renderer and source-reader rules from Lean 0.1.29, retaining doc attributes and legal notices.
The driver inventories Rust sources inside directories named `build` too, and leaves fixtures and documentation inputs authored with a reason.
Form C additionally removes comment-form documentation where the consumer scan allows it.
Explicit `#[doc = ...]` attributes remain byte-identical.
The full compiler lexer checks B with exact token equality, and C with equality after excluding doc attributes from both token listings.
C retains documentation for crates with a detected missing-docs denial, included documentation, or a documentation-consuming macro.
This includes callers of the compiler's `rustc_queries!` macro, whose implementation generates attributes when the original documentation is absent.
Every exception is listed in `source-report.json`.

The manifests bind files, modes and symbolic links.
Cargo checksum changes are restricted to Rust files whose old and new digests are recorded by the qualification pass; a mismatching original fails.
The original source and checksum manifests stay available in the authored tree.
The verifier rejects unrecorded changes and preserved files that changed.
The census tables count every inventoried source file, including preserved fixtures.
Actual compiler input totals require the subsequent build's dep-info.

`build_qualified` remains false: lexer equality does not establish macro, build-script or whole-toolchain correctness.
Before a kit can measure C, build it with the fixed configuration, review any additional doc consumers and prepare corrected source forms on the preparation machine.
Keep the toolkit, source descriptor, preparation script, compiler identity and manifest hashes with the experiment.

The method uses the Rust project's compiler lexer and Debian Rust Maintainers' source packaging.
See the [Rust adapter reference](https://github.com/Sparky-OS/sparky-stereo-os/blob/main/skills/lean-code/references/rust-adapter.md) for source-consumer rules.

## Offline measurement kit

The runner and collectors now implement the remaining experiment. Qualification status belongs in the preparation hand-back: implementation alone is not a passing dry run.

Apply `overlay.py` identically to A, B and C using the edition recipe and Lean toolkit. Start C qualification with `check-c.sh`; use `qualify-tools.sh` for the real stage-1 library/compiler and tool build when combined checks encounter the seed/new-private-rmeta collision, retaining failing crates' docs with `retain_docs.py` and the original preparation ledger. Reconstruct a clean C tree after qualification: generated targets, configured checksums and moved lockfiles do not belong in a sealed source. Bind Debian's build-generated WIT literals too: capture the original producer, project its two Rust literals here, check their tokens with 1.99.1, and let `wit_wrapper.py` retain native regeneration before copying the prepared per-form Rust asset. Restore those generated literals to authored text in rust-src. `archive_batch.py` binds reviewed metadata/assets in an already sealed archive. Run `verify_final.py` against all three clean tree/archive views and independently extract/verify the final transport. The final manifest follows the packaging/native overlay and every build-led doc retention.

`image-prepare.sh` records the signed Debian snapshot and exact installed package versions, installs the named edition seed archives, and enables contained perf counters. Its apt container must start with the edition HTTPS-only helper and mounted CA. Export the resulting immutable image as `image.tar.gz`; preserve its image ID and SHA-256. The measured containers never pull images or access the network.

A kit contains `scripts/` (these tools plus the exact Lean module), `sources/` (three archives, manifests and identities), `subject/` (the named offline regex workspace), `image.tar.gz`, a fixed `plan.json`, `SHA256SUMS`, and executable `run.sh`, `status.sh`, `pause.sh`. `make_plan.py` creates the explicit sequence. A completed local sample must justify its repeated subject and total time budget before shipping it.

The driver uses `nohup`, an exclusive lock and atomic whole-step receipts. Rootful Podman is confined to the kit's `runtime/storage` and `runtime/runroot`, with contained perf capabilities and no host compiler installation. Whole builds use the edition's stage-2 configuration; the interleaved repeated subject builds the full first compiler stage and standard library with code generation. The standard-library hash is discovered from the actual built libstd, substituted only in its packaging metadata, then packages are assembled without a source-clean pass. The package hook verifies/restores authored `rust-src`. Compilation and package assembly have separate counters. Runtime images install the five measured core compiler/runtime archives without a network; runtime workloads use the invoking person's numeric uid/gid with a writable home inside the step.

`measure.py` preserves raw perf and GNU-time output and rejects incomplete measurements. Instructions count the explicit env launcher and inherited user-space tasks. File-capability perf uses secure exec: resolve the intended executable before that boundary and explicitly restore its selected PATH/library path afterwards. The measured version must match; a direct version probe alone is insufficient. GNU time reports maximum child RSS; `memory.peak` reports the container lifetime peak and can include earlier commands. The dep-info census reports unique source inputs and generated files separately, validating every non-generated input against the sealed form. This is source coverage, not repeated physical I/O.

`analyze.py` compares every packaged installed-file payload, aligns Rust content-hash names and build-ID debug companions, and gives ELF section lengths and differing bytes by section offsets. File-offset differences are separate because section-layout shifts move content. Classification distinguishes debug/line records, Rust metadata, build IDs, symbols, relocations, code and constants. Causal attribution of every machine-code, constant or metadata subfield is not claimed: residual categories remain explicit next work. The runtime `/dev/full` panic establishes an actual standard-library location. `rust_location.py` selects the unchanged Rust lexer for these manifest-bound inputs and reuses Lean's content resolver: generic consumer discovery otherwise mistakes a first-line Rust `#![attribute]` for an interpreter. No source or shipped adapter is changed by that explicit resolver selection.

The fixture is deliberately smaller: it compiles a forwarding compiler ELF, assembles a real lc1 package and authored source payload, installs it in a throwaway image, then runs every collector and summary path. Its synthetic panic source exercises resolution; it is not a standard-library result. `test_runner.py` injects decimal, receipt, space and temperature failures. The full dry run must additionally interrupt an actual container step and prove whole-step resume without repeating finished work. Keep both red and green evidence.
