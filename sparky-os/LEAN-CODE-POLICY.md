# Sparky Stereo OS Lean Code policy

## Main principle: prepare ahead of consumption

> Lean Code moves preparation upstream. Like pre-rendering or pre-staging, it prepares what the machine needs before consumption, avoiding repeated work while preserving the original material for people.

**Optimize the path of consumption.** Pre-processing transforms inputs before the main processing step; pre-staging puts data where it will be needed; pre-rendering prepares a visual result before it is requested. Lean Code applies the same principle to code and configuration: retain the complete human-authored source and prepare a verified machine representation before its consumer needs it.

The primary objective is fewer bytes read and scanned, less parsing work and less working space where the consumer benefits. This includes compiler inputs as well as runtime scripts, QML and settings. Removing C/C++ comments reduces text for the compiler to read, scan and discard even when the executable is unchanged. Cached or compiled forms need their own accounting; a source file is not necessarily read on every use.

Measure the files and bytes actually consumed by each operation, then its CPU time, elapsed time and memory. Verification records and human documentation outside that path do not cancel avoided reads there. Account for their storage and for transformation/verification costs separately, including total build or update costs. The analogy explains where work moves; measurements establish how much is saved.

## Release requirement

**Release clarification, Daniel, 2026-10-18:** all packages and ISOs we put live must pass Lean Code in our pipeline. Our preprocessed packages carry the versioned **lc** marker so clients skip completed work. The staged `lc1` implementation, its configuration baseline, separate HR documentation and publication gate are described in [LC-PACKAGES.md](lean/LC-PACKAGES.md). This supersedes install-time-only processing for packages we build and publish; third-party packages installed directly keep their own update sources and the local projection path.

Adopted 9 October 2026. This policy governs the build and packaging pipeline for Sparky Stereo OS distribution ISOs. It specifies release requirements; implementation coverage must be recorded before an image is described as compliant.

Keep the complete, documented source as the authority. Generate the machine representation needed for execution, and make every transformed error location traceable to that exact source. Apply this through the existing build and packaging processes, without refactoring applications, reorganizing repositories, renaming their source files, or changing their upstream development conventions.

The default Stereo ISO contains runtime code and ordinary program documentation. Complete developer source and additional HR documentation remain available as matching source/documentation packages. A compact diagnostic resolver and package identity manifest can ship with the system; their compressed size counts in the net storage comparison.

## Scope and the remaster option

Lean Code is required by the **Sparky Stereo OS ISO profile**. It is an **optional, default-off feature** of general-purpose Sparky remastering. The requirement must live in the Stereo profile, not in the shared remaster tool's unconditional execution path.

The scope includes **every comment-bearing format in the shipped image**, including settings and configuration files, default user profiles, service definitions, templates, scripts, source payloads and text resources. No file class is exempt merely because people traditionally edit or read its comments. The target is zero dispensable comments in the distributed payload. Explanations belong in normal program documentation or the separately available documented source; necessary directives and licence obligations are handled explicitly below. This extends to comments inside documentation formats, while preserving the documentation's actual content.

| Build or remaster context | Lean Code behavior |
| --- | --- |
| Official Sparky Stereo OS distribution ISO | Enabled and required; validate the selected payload and its provenance before packing |
| Ordinary SparkyLinux remaster | Disabled by default; existing remaster behavior remains available |
| User explicitly enables Lean Code | Run the supported build/package projection path and report its coverage |
| User disables the option | Do not initiate transformations or source rebuilds; already-installed MR packages remain as installed |

Maintain the edition's integration as **Sparky Backup Core Stereo**, a separately named `sparky-backup-core-stereo` fork of [SparkyLinux's Sparky Backup Core](https://github.com/sparkylinux/sparky-backup-core). Preserve upstream history, licences and attribution. Give the Stereo package/profile and entry point an explicit Stereo identity; do not silently overwrite the stock tool or make its users adopt this policy. Any generally reusable integration offered upstream must retain the optional behavior.

Selecting the option at remaster time does not retroactively strip comments from compiled binaries. The native work happens earlier, while building packages from source; the packer consumes and verifies those packages. An optional remaster can reuse verified MR packages or invoke the supported source-build workflow. Missing source or unsupported transformations are reported explicitly. Disabling the option must not require the transformation toolchain.

This requirement does not impose a new coding convention or mandatory build step on upstream developers, other Sparky editions, or software a user subsequently builds independently. The release manifest distinguishes our rebuilt packages, transformed text payloads and unchanged third-party binaries; an unchanged artifact is never counted as transformed.

## Provenance and layers

**Where MR/HR comes from.** The policy applies Daniel's dual-code paradigm, published in Knowledge3D before this edition existed:
- [Dual Code Paradigm: Human-Readable (HR) and Machine-Runtime (MR)](https://github.com/danielcamposramos/Knowledge3D/blob/main/docs/DUAL_CODE.md), first committed 28 August 2025 (7cde1d05);
- [HR/MR Standard for Knowledge3D](https://github.com/danielcamposramos/Knowledge3D/blob/main/docs/HR_MR_STANDARD.md), 29 August 2025 (09e12ccf);
- [PM-KR: Machine-Readable (MR) vs. Human-Readable (HR) Dual Versioning Paradigm](https://github.com/danielcamposramos/Knowledge3D/blob/main/docs/W3C/PM_KR_MR_HR_PARADIGM.md), 15 March 2026 (aa3d9c48), written for the W3C PM-KR Community Group; its section "The Problem: Comments as Runtime Waste" is the reason this policy exists.

CGM contributes only its file convention, as a concept: one authored source; the build regenerates an MR file for the machine and an HR companion for people; the documentation comments move from MR into HR; nobody edits MR or HR by hand, every change goes to the source, and errors are traced back to the source through the same renderer. Nothing else of CGM belongs in this policy.

**The layers (Daniel, 2026-10-14: "this apply to our vm code, partner - think about the layers").** Each layer gets its MR at its own stage, once, in the package that owns it; images are assembled from those packages and never swept again:
1. Kernel and drivers (C): MR before compilation; run-time code is unchanged, so the gains are build time and source size.
2. System runtime: init units, shell, Python, configuration; parsed at every start, so MR saves reading and parsing there.
3. Desktop: QML/JS, desktop files, KConfig defaults; parsed at every login and program start.
4. Programs and their data.
5. The procedural VM: the RPN execution engine of the Knowledge3D specifications ([Three Brain System](https://github.com/danielcamposramos/Knowledge3D/blob/main/docs/vocabulary/THREE_BRAIN_SYSTEM_SPECIFICATION.md), "RPN Execution Engine (15-stack VM)") runs procedures as MR and renders HR for people; the same rule holds, and the VM never reads commentary.
6. Images built from the packages: the ISO, VM images and bench roots inherit MR from their packages.

**Measured per layer (Daniel, 2026-10-14: "I see imense potential on the lean code policy to make us the fastest OS - to measure").** Baseline before any change and the same measurements after, on the same machine: boot to desktop, cold start of QML-heavy programs, tool start-up, settings parse, package install time, session memory, ISO and installed size, build time per package. What moves and what does not are both reported.

## Representations

| Representation | Purpose | Distribution |
| --- | --- | --- |
| Authored source | Existing code, comments, notices and build instructions; the authoritative, editable form | Exact source packages and repositories, retained for each distributed build |
| HR | Human explanation and developer documentation derived from the same source; existing documented source can serve this purpose | Normal manuals/help on the ISO; additional developer material available separately |
| MR | Generated execution or compiler input, with removable commentary absent | Runtime packages and ISO where applicable; intermediate build inputs stay in the build directory |
| Transformation machinery | Reproducible renderer, declared language support, versioned options and source-location resolver | Build dependency plus installable diagnostic tools; only needed runtime lookup components on the ISO |

SOURCE is an architectural role here, not a required `.source` filename. CGM's three-file convention informs the relationship, but Sparky's existing file names and directories remain valid. An already lean file may legitimately produce byte-identical output; transformation must not manufacture differences to appear effective.

## What may be removed

Remove explanatory comments and the empty lines created by their removal when the format-specific adapter preserves behavior and source mapping. Ordinary commented-out settings and examples are included; retain useful explanations and examples in normal documentation or the matching documented source instead of keeping them inline in the installed settings. Do not rename variables, rewrite algorithms, reorder declarations, reformat whole projects, or apply unrelated optimizations.

Comments that participate in a tool or runtime contract are not removable prose. This includes interpreter and encoding directives, compiler/build directives, translation annotations until consumed, required notices, and comments read by generators. Preserve strings and embedded languages, including heredocs, regular expressions and raw strings. Preserve the semantics of line-sensitive constructs.

Native build qualification includes every source consumer, not only the C/C++ compiler.
Engine 0.1.9 leaves a C/C++ file unchanged when it carries structured documentation or translation annotations; inserting `#line` between a preserved comment and its declaration can itself break a textual generator.
Engine 0.1.17 writes no `#line`, and the refusal stays: the lines a removed comment empties between a preserved comment and its declaration can confuse a textual generator too.
For other known consumers, retain relative source patterns and their reasons in `debian/sparky-lean-preserve.json`; `lean.debian_prepare --preserve-source PATTERN REASON` creates this plan.
The native source report records each retained file and fails on stale patterns or a changed plan.
XScreenSaver's resource checker and SDL's generated manuals exposed these boundaries during the full repository migration.
Do not disable a checker or drop generated documentation merely to make a projected build pass.

Python docstrings are observable through `__doc__`, and software can use them for help or other behavior. Retain them by default; a package can opt into their removal only after establishing that its supported behavior does not depend on them. Perl POD and other material providing normal program documentation also remain. This is separate from stripping ordinary comment tokens. [Python data model](https://docs.python.org/3.14/reference/datamodel.html), [Python lexical analysis](https://docs.python.org/3.14/reference/lexical_analysis.html).

Retain copyright, attribution and licence material in the forms required by each package. Where the applicable terms allow it, accompanying licence/notice files can carry this material without inline commentary. A generic stripper must not assume relocation is always sufficient: for example, Apache 2.0 has specific requirements for modified files, distributed source notices and NOTICE material. Calling an artifact MR does not by itself settle its legal classification or remove these obligations. Record the applicable requirement and location for each retained notice; do not use a blanket legal exemption for all comments. [Apache License 2.0, section 4](https://www.apache.org/licenses/LICENSE-2.0), [MIT licence](https://opensource.org/license/mit).

Preserve the content of manuals, translations and normal program help. Configuration explanations can move out of the active settings into that documentation; their usefulness is not a reason to exempt configuration comments from projection. Ordinary documentation is distinct from syntactic comments embedded in its source or shipped assets. [Debian documentation and copyright policy](https://www.debian.org/doc/debian-policy/ch-docs.html).

**Where the HR copy of settings lives** (Daniel, 2026-10-14: "keep the config options at a HR copy that's not installed or is shipped at the official documentation place - alongside the debug/decompiler tool and how to use this").
- The installed setting is the lean MR file. Its full HR copy carries every option, every explanation and the disabled examples.
- The HR copy is not on the install ISO. It ships in the package's documentation package at `/usr/share/doc/<package>/hr/<the file's installed path>`, following Debian's place for documentation and examples, and it installs with the system's first update over the internet (Daniel: "the install iso don't ship them, but installs on first internet update", "(the docs)").
  The mechanism is to be chosen and tested: for example, the installed meta-package gains the documentation packages as dependencies in its first online version, or a one-time update step pulls them. Either way the ISO stays lean and an online system gets the full documentation without a manual step.
- It is also published at the edition's official documentation place, beside the source-location resolver (the "decompiler" that maps an MR line back to its HR source) and the resolver's manual: how to look up a line, how to regenerate the HR view of an installed file, and how to report a local edit.
- Each lean file keeps exactly one comment line at its top that points to its HR copy and the online page (Daniel, 2026-10-14: "yes, keep the pointer line"). It is a retained comment, and the coverage manifest records its reason: a person editing `/etc`, even on an offline install before the documentation arrives, can find the explanations. Formats without comments get no pointer.

There is no general Linux rule requiring explanatory comments in installed settings. Debian's configuration rules address location, ownership and preservation of local changes, and do not impose blanket comment retention. Our edition can choose lean defaults while keeping those update semantics. Every retained comment must have a specific semantic or licence reason in the coverage manifest; an unqualified adapter is recorded as unfinished work, not a permanent exemption. [Debian configuration-file policy](https://www.debian.org/doc/debian-policy/ch-files.html#configuration-files).

## Cover the whole stack through the appropriate build stage

| Software family in this initiative | Integration path | Important condition |
| --- | --- | --- |
| Kernel, Mesa, KWin, Qt, Wine/Proton, VLC, FFmpeg, mpv and native engineering applications | Generate validated compact MR source and headers explicitly before invoking the compiler | C/C++ are included; preserve preprocessing semantics, source locations and normal builds from the documented source |
| Python and shell tools, launchers and packaging helpers | Validated language adapter over a disposable staging copy before compilation or package assembly | Preserve help, encoding, quoting, heredocs, imports, permissions and command behavior |
| QML and JavaScript in Plasma, apps and themes | Adapter coordinated with Qt's resource/compiler pipeline and existing JS tooling | Preserve JS line-termination rules, QML directives, URLs, translation extraction and generated resources |
| GLSL and other shader sources shipped as text | Shader-specific adapter before embedding or installation | Preserve version/extensions, macros, string-embedded shaders and driver diagnostics |
| DKMS code and development headers shipped as source | Separate source-payload profile, retaining required notices and correct downstream build behavior | These are source distributions used to build on the recipient machine, not ordinary stripped binaries |
| Rust, Java, Go, assembly, other languages and structured formats as encountered | Qualify a language-specific MR adapter before compilation or packaging | Similar-looking comment syntax is not evidence of equivalent language semantics; unsupported coverage remains explicit |
| Settings and configuration, including `/etc`, packaged default profiles, service definitions and templates | Generate MR defaults before package assembly, including outputs generated for the image | Select the adapter by the actual consumer and grammar; preserve values, precedence, quoting, permissions, required directives and upgrade behavior |
| Comment-bearing markup, stylesheets, documentation assets and other text resources | Qualify the appropriate format adapter at the stage that creates the shipped artifact | Remove dispensable syntactic comments while preserving visible documentation, literal data and any behavior that consumes comment nodes; binary/media payload is not text to scan |

C and C++ must pass through the explicit pre-compilation MR step in our ISO package builds. The goal is to present less source text to the compiler, including fewer removable comment and blank lines. C and C++ keep one exception, because their compiler reads line numbers (`__LINE__`, `assert`, diagnostics, debug line tables): a removed comment leaves the line breaks it held, and their blank lines are not collapsed, so every authored line keeps its number with no `#line` directive. Engines up to 0.1.15 wrote `#line` after every removed run instead, and GCC spent more on those directives than the comments cost: against Debian's libstdc++ headers, 23.7% more instructions to preprocess a small program, where the line-keeping form of engine 0.1.17 spends 1.9% fewer (ORDER 303, with the public proof page docs/proofs/lean-code-compile-cycles.md and its scripts). The compiler's existing comment removal does not satisfy this additional policy requirement. Process reusable headers as well as translation units, and cache validated MR by exact source, renderer and option identity so repeated builds can reuse it.

The adapter must respect translation-phase ordering, token boundaries and the original meaning of `__LINE__`, `__FILE__`, line-sensitive macros and source-location builtins. The origin mapping must participate in preprocessing/compiler source-location handling as necessary, not merely rewrite a diagnostic after the value has already changed. A location-aware input adapter or preprocessing bridge is an implementation requirement; the present text strippers are not a substitute. Preserve comment consumers until their input has been consumed, and never compact whitespace inside a literal. Ordinary syntax, type checking, preprocessing and code generation still belong to the compiler.  [GCC initial processing](https://gcc.gnu.org/onlinedocs/cpp/Initial-processing.html), [GCC predefined macros](https://gcc.gnu.org/onlinedocs/cpp/Standard-Predefined-Macros.html).

Run source-dependent generators against their intended input. For example, Qt translation extraction consumes comment annotations; stripping must not remove them before that stage. Embedded and generated outputs need their own provenance chain. [Qt translation annotations](https://doc.qt.io/qt-6/i18n-source-translation.html).

## Error locations belong to the authored source

The renderer emits MR and an origin mapping from the same parsing decisions. It must not infer origins later by searching for a matching line of code: repeated statements would make that ambiguous. Do not pad MR with blank lines or insert tracking banners to preserve apparent line identity. C and C++ are no padding: the line breaks they keep are the removed comments' own, because their compiler needs the authored line numbers and no map can take part inside it.

The default mapping mechanism is reconstruction on demand: obtain the exact source and renderer version, regenerate MR and the map, verify the generated MR digest against the distributed artifact, and translate the reported line and column. Cache the result by source digest, renderer digest and options. A comment-only source edit can leave MR unchanged while moving source lines, so an MR hash alone is not a sufficient cache key.

Each build records the source package/version, architecture, source snapshot and patch hashes, renderer identity/options, generated-file hashes, installation-path mapping and, for native binaries, their build IDs. Logs and crash reports carry the corresponding build identity. Never resolve an old crash against an arbitrary current checkout merely because the file has the same name.

| Diagnostic | Resolution path |
| --- | --- |
| Compiler error in transformed text | MR file/line/column → verified renderer map → authored source file/line/column |
| Python, shell, JS or QML error | Runtime-specific location parser → exact package artifact → verified map |
| Configuration parse error | Consumer-specific location parser → verified installed defaults or image artifact → authored configuration map; report local edits as unmatched unless their own mapping exists |
| Native crash address | Matching binary build ID and debug symbols → compiler source position → authored source directly, or MR mapping if an additional projection actually occurred |
| Generated code or embedded resources | Compose each recorded generation mapping; otherwise identify the generated location honestly |

Keep the original diagnostic as evidence and present the resolved authored-source location first. Missing source, mismatched hashes, unsupported formats, ambiguous positions or unavailable debug symbols produce an explicit unresolved result. They never produce a guessed line. A location mapping cannot recover a native stack frame that the available debug information does not describe. [GDB separate debug files and build IDs](https://sourceware.org/gdb/current/onlinedocs/gdb.html/Separate-Debug-Files.html).

Adopt standard source maps where a toolchain already supplies them, with a bridge to the package manifest. Account explicitly for each format's line/column units, such as byte offsets versus UTF-16 positions. [ECMA-426 source maps](https://ecma-international.org/wp-content/uploads/ECMA-426_1st_edition_december_2024.pdf).

With MR-only runtime code on the ISO, source-level display requires the matching source to be cached, installed from source media, or retrieved on demand. The resolver remains useful offline when those artifacts are present. Normal program documentation cannot substitute for the exact source bytes needed to reconstruct a code location.

## Build and package integration

1. Freeze the package inputs: upstream source, downstream patches, packaging and toolchain identity. Continue reviewing and editing these existing sources normally.
2. Run source consumers such as translation extraction and code generation at the correct stage. Build a disposable output/staging tree with the same relative layout.
3. Generate a validated explicit MR projection before compilation and packaging, including C/C++ source and headers in every package we rebuild for the Stereo ISO, and every supported comment-bearing configuration or resource payload. Produce provenance and mappings as part of that operation. Never rewrite the working checkout or the running system's installed files.
4. Run the relevant existing tests on the actual projected/compiled artifacts, plus language-edge and diagnostic-mapping tests. Package the tested outputs.
5. For text installed by a custom package builder, place its approved projection after payload staging and before bytecode generation, resource compilation, size calculations and checksums as applicable. Keep package metadata and Multi-Arch shared files consistent.
6. Publish matching source packages, renderer versions and debug artifacts alongside the binaries. Keep original upstream archives and downstream changes in the source-package form expected by Debian tooling. The source package must rebuild the same artifacts without requiring an undocumented private tool. [Debian source package policy](https://www.debian.org/doc/debian-policy/ch-source.html).
7. Let `sparkybackup` assemble those packages into the ISO. The packer must not perform a blind final sweep over installed files, which would bypass package tests and invalidate ownership/checksum expectations.

For conventional `dh` packages, `python3 -m lean.debian_prepare` records the native-source and payload stages in the retained Debian source. The edition's reviewed CEC, Cushion Swap and memory-settings builders instead use `python3 -m lean.debian_custom`: their authored `build.sh` remains intact, while a derived recipe retains compilation and staging, then performs the checked payload assembly. Debian builds the source archive before that recipe runs. Unknown assembly or post-assembly conventions are rejected for explicit integration. Both adapters accept `--build-dependency` so a prerequisite discovered in a clean build is retained in `debian/control`, rather than supplied only by the coordinator's machine.

For package-owned settings, build the lean default into the owning package so package checksums and the configuration baseline describe the bytes actually distributed. Rebuild or properly repackage third-party defaults through that path instead of modifying installed conffiles behind the package manager. Keep locally edited settings intact during later upgrades; this policy governs our image, not users' subsequent edits. Image-owned defaults and generated files need an equivalent staged transform, provenance and validation. Check the completed image for generators that have reintroduced comments after the earlier projection. Remastering must work on its disposable image staging copy, never strip the running host's settings.

Configuration adapters must be qualified against the actual parser and version; `.conf` is not a grammar. Test effective values and order, includes, quoted comment characters, multi-line values, disabled examples, parser diagnostics and package install/upgrade behavior. A retained operational directive is not an explanatory comment simply because its syntax begins with a comment marker. Required notices and directives must appear as reasoned exceptions in the release coverage report.

An unsupported transformation is recorded as incomplete coverage. A failure for an enrolled package stops that package build; it must not silently ship an unverified projection or count the compiler's ordinary comment removal as the required C/C++ pass. The Stereo ISO release profile must report unresolved coverage and must not label an incomplete image compliant. General remastering with the option off remains available.

## Adoption sequence and acceptance

First establish one shared manifest/resolver contract and a package census. Pilot small Sparky-owned scripts with ordinary comments, retaining normal help and notices. Prove successful and intentionally failing runs resolve to the exact authored source, including after a comment-only edit and when presented with stale artifacts.

Qualify the C/C++ source-and-header adapter, compiler-location integration and native crash mapping as part of this implementation, alongside the small script pilot and representative configuration consumers. Then qualify QML/JS, larger interpreted packages, remaining configuration grammars and other comment-bearing payloads separately. C/C++ participation is required regardless of whether the final native binary becomes smaller. Coverage is measured against all comment-bearing formats in the selected image, not just the first adapters implemented.

Acceptance requires deterministic output for fixed inputs; preservation of language semantics and supported program behavior; reliable source locations; complete source/build provenance; passing existing package tests; and a measured compressed footprint including any additional tools and metadata. Adapter tests cover comment-like text in strings, token boundaries, line continuation, Unicode columns, repeated statements, generated code and comment-only changes. Passing tests are evidence for the declared scope, not proof for every language construct.

## Build time accounting

Reducing the compiler's text input is a design objective. Measure its actual timing benefit rather than treating every removed line as a fixed unit of saved time. The MR stage itself must read and classify the original source, and filesystem work, preprocessing, compilation and linking contribute differently to elapsed time.

Compare the same source revision, compiler/options, dependencies, parallelism and hardware under controlled load. Report both compiler-stage time and total source-to-package time, including MR generation and mapping. Include a cold build, a warm build with validated MR cached, an incremental code edit and a comment-only edit. Record source/header bytes and lines removed, transformation CPU/wall time, compiler CPU/wall time, peak memory and total build time. Keep compiler caches comparable. A reusable MR cache can amortize generation; it must never reuse a stale source map after a comment-only edit.

Build-time results are separate from ISO-size results. A smaller compiler input may leave the binary byte-identical. No measured build-time gain is claimed by the policy itself.

## Space accounting

Report the final ISO difference, not the sum of repository comments or downloaded `.deb` sizes. Keep source-tree size, installed-file size, compressed package size, compressed live filesystem size and final ISO size as distinct measurements.

The release comparison uses the same frozen package set, timestamps, filesystem ordering, compression settings, architecture and boot assets. Its net saving is:

```text
baseline ISO bytes − Lean Code ISO bytes
= removed compressed runtime payload
  − added resolver, manifest and dependency payload
  + filesystem packing effects
```

An MR-only ISO still includes normal program documentation. Additional source/HR bundles remain off the default ISO under this policy. Report their size separately if a developer/source edition is produced. Do not apply historical HR/MR source percentages to the ISO or claim RAM/FPS improvements from comment removal.

A full paired ISO build is the release measurement. Keep dated source snapshots, sample estimates and build-time experiments in the release evidence; sample projections must not be presented as a measured final ISO saving.

The initial 9 October 2026 estimate covered a bounded set of installed code files; it did not measure `/etc` or the full range of configuration/resource formats now explicitly included. The later same-day expanded study samples settings and additional resource/documentation/source formats separately. Keep those measured populations, exclusions and compressed contributions explicit. Do not present the earlier 2.20 MiB gross projection as an estimate of the entire expanded policy, add it twice to the expanded total, or assign unmeasured savings to settings.

## Install-time projection: dpkg-stereo (Daniel, 2026-10-09)

Lean Code is about what the running system reads: every read counts (shell scripts and configuration parsed at each start, QML/JS, shaders, text resources). The authored source stays the authority and becomes more verbose, not less: comments are documentation tier zero, projected into each audience's documentation, while the runtime reads the lean form.

Packages from other sources (Debian, deb-multimedia, third parties) are not repackaged to strip them. They install unchanged, the same signed `.deb` files, and **dpkg-stereo** projects their supported text payloads locally, at install time, through the same qualified adapters. This keeps the edition a direct derivative: Debian's packages stay Debian's.

- **When:** after dpkg has installed or upgraded packages (APT `DPkg::Post-Invoke`), for the files of the packages just changed. It is a recorded, per-package, reversible step, not a blind sweep.
- **Record:** `/var/lib/dpkg-stereo/` keeps, per file, the package and version, the original hash (dpkg's own), the lean hash, the adapter identity and options. The original bytes are not stored: they are reconstructed on demand from the exact package version (apt cache or archive), as the diagnostic resolver already does.
- **Conffiles:** a stripped conffile would look user-modified to dpkg and prompt at every upgrade. Before dpkg runs (`DPkg::Pre-Invoke`), each conffile whose bytes still equal our recorded lean hash is restored to its pristine package version; dpkg upgrades it normally; after dpkg, it is projected again. A conffile the user edited (lean hash no longer matches) is left alone and handled by dpkg's usual rules. Users' edits are always preserved.
- **Verify:** `dpkg-stereo --verify` checks each projected file against its lean hash and, by re-projecting the package's original, the original against dpkg's md5sums; `debsums`-style checks go through it.
- **Exclusions:** licence and copyright files, `/usr/share/doc`, manuals, translations, behaviour-affecting comments (interpreter lines, directives, annotations still to be consumed), and every format without a qualified adapter, which stays untouched and is listed as uncovered.
- **Way back:** `dpkg-stereo restore <package>` (or globally) returns the original files; a package or path can be held out permanently. The feature follows the same switches as the remaster option: required for the Stereo ISO profile, default-off elsewhere.

Phasing for the first Stereo ISO (Daniel, 2026-10-09, accepting the main session's suggestion): the explicit C/C++ pre-compilation pass applies to what we build (our packages and the stereo stack we compile anyway); dpkg-stereo covers installed text through the qualified adapters, starting with shell, configuration grammars, QML/JS and shaders; one real package (KWin) is measured end to end.
