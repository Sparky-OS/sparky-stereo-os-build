# The Python find and context engine, kept as the oracle

What it was: `tools/skills-context.py` of Sparky-OS/sparky-stereo-os at the commit in `data/golden/SOURCE` (with its two test files), the engine behind `sparky-stereo-skills find` and `context`.
Whether a skill's package was installed was never asked of it, so `find` could point to a skill whose program was absent.

What replaced it: the Zig engine under `compiled/`, reached through `surfaces/cli` (and `surfaces/mcp`).
It reproduces this tool's rank, scores to two decimals, `context` text byte for byte and `sections` list, checked against goldens recorded from it (`data/golden/`, `tests/L1_domain/`), and it adds the installed check in one place for every door.

Why it stays: it is the reference the goldens were recorded from, and the way to regenerate them.
Nothing is deleted.
The public copy in Sparky-OS/sparky-stereo-os stays in place until the package's bash helper delegates `find`, `list`, `context` and `sections` to the Zig program; the move of that public file is part of that package change.
Differences by design: `--find`, `--list`, `--list-sections` are the verbs `find`, `list`, `sections`; `--bundle` stays the helper's `export`; eligibility is applied unless `--all`.
