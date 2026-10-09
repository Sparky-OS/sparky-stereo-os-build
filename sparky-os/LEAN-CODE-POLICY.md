# Sparky Stereo OS Lean Code policy

Adopted 9 October 2026. This policy governs the build and packaging pipeline for Sparky Stereo OS distribution ISOs. It specifies release requirements; implementation coverage must be recorded before an image is described as compliant.

Keep the complete, documented source as the authority. Generate the machine representation needed for execution, and make every transformed error location traceable to that exact source. Apply this through the existing build and packaging processes, without refactoring applications, reorganizing repositories, renaming their source files, or changing their upstream development conventions.

The default Stereo ISO contains runtime code and ordinary program documentation. Complete developer source and additional HR documentation remain available as matching source/documentation packages. A compact diagnostic resolver and package identity manifest can ship with the system; their compressed size counts against any savings.

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

Python docstrings are observable through `__doc__`, and software can use them for help or other behavior. Retain them by default; a package can opt into their removal only after establishing that its supported behavior does not depend on them. Perl POD and other material providing normal program documentation also remain. This is separate from stripping ordinary comment tokens. [Python data model](https://docs.python.org/3.14/reference/datamodel.html), [Python lexical analysis](https://docs.python.org/3.14/reference/lexical_analysis.html).

Retain copyright, attribution and licence material in the forms required by each package. Where the applicable terms allow it, accompanying licence/notice files can carry this material without inline commentary. A generic stripper must not assume relocation is always sufficient: for example, Apache 2.0 has specific requirements for modified files, distributed source notices and NOTICE material. Calling an artifact MR does not by itself settle its legal classification or remove these obligations. Record the applicable requirement and location for each retained notice; do not use a blanket legal exemption for all comments. [Apache License 2.0, section 4](https://www.apache.org/licenses/LICENSE-2.0), [MIT licence](https://opensource.org/license/mit).

Preserve the content of manuals, translations and normal program help. Configuration explanations can move out of the active settings into that documentation; their usefulness is not a reason to exempt configuration comments from projection. Ordinary documentation is distinct from syntactic comments embedded in its source or shipped assets. [Debian documentation and copyright policy](https://www.debian.org/doc/debian-policy/ch-docs.html).

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

C and C++ must pass through the explicit pre-compilation MR step in our ISO package builds. The goal is to present less source text to the compiler, including fewer removable comment and blank lines. The compiler's existing comment removal does not satisfy this additional policy requirement. Process reusable headers as well as translation units, and cache validated MR by exact source, renderer and option identity so repeated builds can reuse it.

The adapter must respect translation-phase ordering, token boundaries and the original meaning of `__LINE__`, `__FILE__`, line-sensitive macros and source-location builtins. The origin mapping must participate in preprocessing/compiler source-location handling as necessary, not merely rewrite a diagnostic after the value has already changed. A location-aware input adapter or preprocessing bridge is an implementation requirement; the present text strippers are not a substitute. Preserve comment consumers until their input has been consumed, and never compact whitespace inside a literal. Ordinary syntax, type checking, preprocessing and code generation still belong to the compiler.  [GCC initial processing](https://gcc.gnu.org/onlinedocs/cpp/Initial-processing.html), [GCC predefined macros](https://gcc.gnu.org/onlinedocs/cpp/Standard-Predefined-Macros.html).

Run source-dependent generators against their intended input. For example, Qt translation extraction consumes comment annotations; stripping must not remove them before that stage. Embedded and generated outputs need their own provenance chain. [Qt translation annotations](https://doc.qt.io/qt-6/i18n-source-translation.html).

## Error locations belong to the authored source

The renderer emits MR and an origin mapping from the same parsing decisions. It must not infer origins later by searching for a matching line of code: repeated statements would make that ambiguous. Do not pad MR with blank lines or insert tracking banners to preserve apparent line identity.

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
