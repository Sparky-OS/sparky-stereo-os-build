# Preparing Rust compiler sources for a Lean Code comparison

This is the source-preparation part of an experiment on rustc 1.99.1+dfsg1.
It prepares the files before they go to a measurement machine.
The build runner and hardware measurements are a later step.

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
The eventual unattended build runner needs its own continuously sampled guard.

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
