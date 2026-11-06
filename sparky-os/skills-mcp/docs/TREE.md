# The skills server: its tree and what each path claims

Daniel's choice (2026-11-06, ORDER 430): the server is written in cgm-zig, hyper-modular, with everything a variable.
A path here reveals four things: the concern root, the level, the artifact projection and the owner.
This page is the plan the tree follows; `tests/lint/` fails when the tree stops following it.

## The product and its doors

One product, `skills-mcp`, one engine, three doors onto it.
- The engine is `compiled/`: it knows skills, where they live, which are installed, how to rank, read, bundle and run them.
- Door 1, the command line (`surfaces/cli/`): `sparky-stereo-skills find|list|context|sections|bundle|commands|run|mcp ...`.
- Door 2, the MCP server (`surfaces/mcp/`): `sparky-stereo-skills serve`, stdio only, started by an assistant.
- Door 3, the person's dialog and the folders: the existing helper (`link`, the dialog, `export`) stays in the package's shell helper and calls door 1.
  It is not rewritten here, so it has no folder in this tree.
- Same canonical engine for a person at a terminal, a dialog and an assistant, never a copy of it per door.

## Concern roots

| Root | Holds | Ownership |
| --- | --- | --- |
| `compiled/` | the engine, Zig source with its comments (the authored truth) | engine |
| `surfaces/` | the doors and their verb taxonomy; they call the engine, they hold no skill logic | doors |
| `data/` | fixtures, goldens, the nine languages' strings, schemas; no code | data |
| `runtime/` | the format of the person's saved choices (what the program reads and writes at run time) | engine |
| `tools/` | build-time helpers that the build and the tests share (the `_kinds/` scanner) | build |
| `scripts/` | shell runners that start a container to build and test | build |
| `envs/` | the container recipe the tests run in | build |
| `tests/` | one folder per concern root and level that it tests, mirrored | tests |
| `docs/` | this tree, the contract, the design check | docs |
| `old_attempts/` | the Python reference engine that the Zig engine must equal, kept until the Zig one passes its goldens, then moved aside, never deleted | none |

Mirroring: every level folder under `compiled/` has the same-named folder under `tests/`.
There is one product, so nothing is shared by two products and there is no `common/`; the day a second product needs a piece, that piece moves to `common/` in both and the half-mirror rule applies.
Lean Code makes the runtime and human readable projections at packaging; this tree holds only authored sources, with no `.source` files (memory sparky-stereo-os-lean-code-policy).

## Levels in `compiled/`

Dependencies point one way, from the top of this list down to the primitives; a lower level never imports a higher one.
My reading of the doctrine's order "L1 domain ... L6 primitive" is: L6 is the bottom, an L5 executable composes L4 atoms (so L4 sits below L5 although its number is smaller), then L3, L2, L1.
The lint rank is therefore primitive 0, atomic 1, executable 2, organization 3, context 4, domain 5.

| Level | Folder | Holds | May import |
| --- | --- | --- | --- |
| L1 domain | `L1_domain/skills/` | the domain facade `engine.zig`: the one API every door calls | L2 and below |
| L2 context | `L2_context/` | one session's context: the person's saved choices, the environment, the skill kinds (`_kinds/skill_kind/`) | L3 and below |
| L3 organization | `L3_organization/` | the catalogue: roots found, skills read, eligibility applied, one list of skills | L5 and below |
| L5 executable | `L5_executable/` | the operations, each the minimal composition of atoms: `find`, `list`, `sections`, `context`, `read`, `commands`, `run` | L4 and L6 |
| L4 atomic | `L4_atomic/<atom>/` | single-responsibility modules, each with `atom.zig` and `CONTRACT.md` | L6 and other atoms only through the catalogue's types, never upward |
| L6 primitive | `L6_primitive/` | files, environment, dpkg status, SHA-256, line framing, process spawn: the platform | the Zig standard library only |

`surfaces/` imports `L1_domain` and `L6_primitive` only (framing and terminal I/O are primitives); it never reaches an atom or an operation.

## Everything is a variable: the `_kinds/` registries

A variant is a file dropped into a `_kinds/<registry>/` folder; the parent discovers it and holds no list.
Hardcoding a variant in a parent is a halt condition, and `tests/kinds/` fails on it.
Zig has no run-time directory discovery, so discovery happens in the build: `tools/kinds_scan.zig` lists a registry folder and `build.zig` generates one module per registry (`kinds_<registry>`), a sorted tuple of the folder's files.
Adding a variant is adding a file; removing one is removing it; no existing reference breaks.

| Registry | Folder | One file per | The file exports |
| --- | --- | --- | --- |
| era | `surfaces/mcp/_kinds/era/` | protocol era (`legacy_2025_11_25`, `stateless_2026_07_28`) | `id`, how to recognise a request of that era, the shape of its replies |
| tool | `surfaces/mcp/_kinds/tool/` | MCP tool (`skills_find`, `skills_list`, `skills_sections`, `skills_context`, `skills_read`, `skills_commands`, `skills_run`) | name, JSON Schema, annotations, handler calling the engine |
| assistant | `surfaces/cli/_kinds/assistant/` | AI assistant (`claude_code`, `codex`, `gemini_cli`, `opencode`, `cline`, `cursor`, `copilot_print`, `goose_print`) | how to detect it, its register and unregister argv, where its configuration lives |
| skill kind | `L2_context/_kinds/skill_kind/` | kind of skill (`user`, `developer`) | the folder name, whether translations are required, whether commands are allowed |
| language | `data/_kinds/lang/` | language (`en`, `pl`, `pt_BR`, `fr`, `de`, `ja`, `ko`, `zh_CN`, `zh_TW`) | the strings file for that language |

A new assistant, protocol era, tool, skill kind or language is a new file.
A new domain is a new folder under `L1_domain/`.

## One file, one responsibility

When a file has two of: several responsibilities, mixed concerns, several public entry points, it is split into one atom per responsibility under a topic folder with a `_topic_summary.md`, and the old path stays as a thin entry point.
Every folder under `compiled/` and `surfaces/` carries a `_topic_summary.md` of at most ten lines.

## Which parts exist at milestone 2b

Present: every level and door below, working and tested.
- L6: `fsio`, `dpkg_status`, `proc`, `sha256`, `jsonargs`.
- L4 atoms: `frontmatter`, `pathsafe`, `eligibility`, `manifest`, `lang_lookup`, `command_gate`, `ai_detect`, `rank`, `sections`, `budget`, `ratelimit`, `skill_uri`, `skill_record`, `statefile`, `slot_class`, `command_spec`.
- L5 operations: `op_find`, `op_list`, `op_sections`, `op_context`, `op_read`, `op_manifest`, `op_commands`, `op_run`.
- L3 `catalogue`, L2 `session`, L1 `skills/engine`.
- Doors: `surfaces/main.zig`, `surfaces/cli/verbs.zig`, `surfaces/mcp/server.zig`; kinds: two eras, five assistants, seven tools, two skill kinds, nine languages.
- Registries and what a new variant needs: an assistant is one file with its program, home folder and register, unregister and list commands; a tool is one file with name, description, schema, `read_only` and `call`; an era is one file with `id`, `revision` and `recognises`; a language is `<id>.zig` and `<id>.json` with the same keys as English; a skill kind is one file with `folder` and its three flags.
Not here: the package that carries the program (see the report), the dialog (the bash helper), the optional ranker (not asked for).
