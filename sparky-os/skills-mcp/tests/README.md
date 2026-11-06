# Tests at milestone 2a

`OUT=/scratch SKILLS_SRC=/path/to/public/checkout scripts/run-tests.sh [filter]` builds every `tests/**/*_test.zig` into a static binary with the station's cgm-zig and runs each in a container (no network, no core dumps, ordinary user, product tree read only).
`OUT=/scratch scripts/negative-controls.sh` shows the two lint tests going red on a copy that breaks the rule.

| Test file | Checks | State at 2a |
| --- | --- | --- |
| `L6_primitive/sha256_test` | SHA-256 hex of "" and "abc" (FIPS 180-4 vectors) | green: the control that the harness can pass |
| `L4_atomic/manifest_test` | the Skills extension's example digests and sizes (151, 29, 35 bytes) from the fixture files | red, `NotImplemented` |
| `L4_atomic/frontmatter_test` | plain, `>-` block scalar, `metadata: requires-packages`, unterminated front matter | red |
| `L4_atomic/pathsafe_test` | names; `..`, absolute, NUL, `%2e`, backslash; resolved path outside the root | partly red (the stub refuses everything, so the refusals pass vacuously until the positive cases pass) |
| `L4_atomic/eligibility_test` | empty field, single package, `a | b`, a name that only contains an installed name | partly red (same reason) |
| `L4_atomic/lang_lookup_test` | whole locale, bare language, Chinese territory kept, English | red |
| `L4_atomic/command_gate_test` | Daniel's second choice: every cell of policy by AI tool by marking by door, and the unlisted command | red |
| `L4_atomic/ai_detect_test` | how "uses AI tools" is found | red |
| `L4_atomic/rank_test` | the scoring arithmetic on a three skill world, by hand | red |
| `L5_executable/find_golden_test` | 33 rows (11 queries, top 3) equal to the Python engine's | red |
| `surfaces/era_test` | the two eras are registered; which request belongs to which | partly red |
| `surfaces/assistant_test` | the exact register and unregister argv per assistant | red |
| `surfaces/lang_test` | nine languages, same keys and placeholders as English | green (data) |
| `kinds/dropfile_test` | the scanner: adding a file adds a variant, removing takes it away | green (the mechanism) |
| `lint/layers_test` | no upward or file-path import; surfaces reach only the engine and primitives; mirror and summaries present | green (the structure) |
| `lint/no_hardcoded_variants_test` | no parent names a variant | green (the structure) |
