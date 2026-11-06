# Tests at milestone 2b

`OUT=/scratch SKILLS_SRC=/path/to/public/checkout scripts/run-tests.sh [filter]` builds every `tests/**/*_test.zig` into a static binary with the station's cgm-zig and runs each in a container (no network, no core dumps, ordinary user, product tree read only, a tmpfs at /tmp).
`OUT=/scratch scripts/e2e.sh` runs the program itself through the command line, MCP in both eras, registration with stub assistants and the command gate (`AS_ROOT=1` for the root refusals).
`OUT=/scratch scripts/negative-controls.sh` and `scripts/mutation-controls.sh` show the lint tests and seven engine rules going red when the rule is removed.

Unit and integration tests (Zig): every atom, `kinds/dropfile`, `lint/layers`, `lint/no_hardcoded_variants` (every variant id, `en` and `user` included), `surfaces/{era,assistant,lang}`, and under `L1_domain`: `engine_test` (trees in a scratch folder: a package adds and loses a skill, eligibility, ambiguity, unknown kinds, `paths.d`, read containment including a symlink out, the extension's example digests), `find_golden_test` (33 rows equal to the Python engine on the real skills tree), `context_golden_test` (context, sections, section plus reference, over budget: byte for byte), `gate_run_test` (the policy both ways, remembered, unlisted commands, slot validation, the reduced environment).
