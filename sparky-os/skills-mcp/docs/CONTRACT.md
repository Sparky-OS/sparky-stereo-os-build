# The engine's contract

The engine is the same whichever door asks.
Every function below is in `L1_domain/skills/engine.zig` at the end; the atoms under it have their own `CONTRACT.md`.
Names are fixed here so the doors and the tests can be written first.

## Words

- A skill: a folder `<root>/<kind>/<name>/` with a `SKILL.md`; `name` equals the folder name and matches `[a-z0-9]+(-[a-z0-9]+)*`, at most 64 characters (agentskills.io specification).
- A root: a directory the engine reads. Order and meaning follow the freedesktop Base Directory Specification 0.8: `$XDG_DATA_HOME` first, then each of `$XDG_DATA_DIRS`, the first the most important, a missing directory skipped; plus the trees named in `<dir>/agent-skills/paths.d/*.conf` (one line `<kind> <absolute path>`).
- A kind: the name of the folder under `agent-skills/`: `user` or `developer`. An unknown kind folder is reported by name, never ignored.
- An origin: `system` for a root from `$XDG_DATA_DIRS` or `paths.d`, `user` for `$XDG_DATA_HOME`.
- Eligible: installed. A skill without `requires-packages` is eligible. With `requires-packages: a | b`, it is eligible when at least one alternative is installed. The set of installed packages is dpkg's status file; `SPARKY_STEREO_PACKAGES` (space separated) replaces it for tests, as the shell helper does today.

## Operations (L5), all read only

| Operation | Takes | Returns | Equal to |
| --- | --- | --- | --- |
| `find` | query text, limit (default 3, 1 to 10), `all` (default false) | ranked rows: rank, name, score with two decimals, description, path, origin | the Python `--find`, rank and score, for the goldens in `data/golden/` |
| `list` | optional kind, `all` | name, kind, origin, description of every eligible skill | `link`'s set of skills; `list` and `link` must agree |
| `sections` | skill name | the exact headings | `--list-sections` |
| `context` | skill names, sections, references, `max_chars` (default 48000) | the text, byte for byte as the Python `render` | the Python `render`; over budget is an error whose text is the old sentence "Nothing was truncated" |
| `read` | skill name and file, or a `skill://` URI | one file, at most 256 KiB, valid UTF-8 | `resources/read` |
| `manifest` | skill name | URI, `sha256:` digest and size of every file; at most 512 files and 16 MiB | the Skills extension's `resources` array |
| `commands` | skill name | the commands the skill lists, each marked `assistant` or `person` | new |
| `run` | skill name, command id, slot values, who approved | the process result and whether `expect` matched | new, behind the gate |

## Errors

A failure is a value, never a crash and never an empty success: `error.InvalidArgument`, `error.NotFound`, `error.Refused` (path or size rule), `error.Ambiguous` (one name in two origins; the message lists both URIs), `error.NotImplemented` (only while a stub), `error.NeedsConfirmation` (the gate), `error.NotEligible` (reported with `all` off only for an explicit name).
Each carries a plain sentence for the person: what failed, why, what to do.
Nothing is retried on another path behind the person's back.

## Atom contracts at milestone 2a

- `frontmatter.parse(text)`: `name`, `description` (plain, quoted or `>-` block scalar), `requires_packages` (the raw `a | b` text) from `metadata:`; an unterminated front matter is `error.InvalidArgument`.
- `pathsafe.check(root, rel)`: returns the joined path or `error.Refused` for an absolute path, `..`, a NUL, a percent-encoded dot, a backslash, or a skill name that breaks the name rule.
  A symlink that leaves the root is refused by `pathsafe.checkResolved`, which sees the resolved path.
- `eligibility.allowed(field, installed)`: the `a | b` rule above; an empty field is allowed.
- `manifest.entry(uri, bytes)`: `{uri, digest "sha256:<hex>", size}`; the digests of `data/fixtures/pdf-processing/` equal the Skills extension's own example (SKILL.md 151 bytes, 99b73749...ab19e; invoice.md 29, 61f4ea6d...d9ee; purchase-order.md 35, f2ff774b...c158).
- `lang_lookup.pick(available, locale)`: the whole locale (`zh_TW`), then the bare language (`fr` serves `fr_CA`), then `en`; Chinese keeps its territory (the edition's nine languages keep their territory).
- `command_gate.decide(policy, ai_tool_found, command, via)`: the rule for running a command a skill lists, as a function.
  Policy `auto` (default): an AI tool found means the command may run at the assistant's own approval; none found means the person confirms first.
  Policy `assistant` and policy `ask` force either way; both are options.
  A command marked `person` always asks the person.
  It returns `.run`, `.ask_person` or `.refuse` with a reason, and never `.run` for a command not in the skill's `commands.json`.
- `ai_detect.found(assistants, probe)`: true when any assistant kind's detection finds its program on `PATH` or its configuration folder in the person's home.
  The result lists which assistants, so the person can see why (see "How the server knows the person uses AI tools" in the report).
- `rank.score(...)`: the Python scoring (fields name 3.0, readme task table 2.0, description 1.0; weight `ln(1 + (N - n + 0.5) / (n + 0.5))`), reproduced from the goldens.

## Decisions made while building (2b)

- A command slot names a class, not a regular expression: `word`, `int` or `enum:a,b,c` (`slot_class`). Zig's standard library has no regular expressions, and a fixed class cannot be made to run for ever on crafted input. `expect` offers `exit` and `stdout_contains`.
- A child process gets only `LANG`, `HOME`, `XDG_*` and a fixed `PATH=/usr/bin:/bin`, runs without a shell, for at most 30 seconds, with at most 16 KiB of output, and never as root.
- `list`, `find`, `context`, `sections`, `read`, `manifest` and `commands` serve only skills whose package is installed (dpkg's status file, or `SPARKY_STEREO_PACKAGES`); `--all` (find, list) shows the rest. An unreadable status file stops the program with a message; it never serves everything.
- Through the command line the person is always asked before a command runs; through MCP the decision is the gate's. A command that needs the person's yes when no confirmation channel exists (this server implements none) is refused with the line to run by hand.
- Front matter reaches MCP clients as a JSON object from a YAML subset (scalars, `>` and `|` block scalars, one nested mapping, `- item` lists); scalars stay strings.
- `skill://<origin>/<kind>/<name>/<file>`: the name is the segment before the file, as the Skills extension requires; a name in two origins is refused with both addresses until the origin is given.
- The era of a request is asked of the era variants; `server/discover` needs `params._meta`. The shape of the `server/discover` result (supportedVersions, capabilities, serverInfo, instructions) is not on the saved evidence pages and rests on the 2026-07-28 base specification, which this lane could not re-read offline: check it against a real client before release.
