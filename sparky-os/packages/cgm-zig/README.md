# cgm-zig Debian package recipe

The package builds Daniel Campos Ramos's patched Zig compiler from source in Debian sid on amd64.
The compiler stays in [his personal repository](https://github.com/danielcamposramos/cgm-zig).
`source.env` pins source commit `0399d2b19b71ed865cc2e6d5e21224f124e373db` and compiler version `0.16.0+cgm.0399d2b19b`.

## Source and build

Build the Dockerfile with `--platform linux/amd64` and a locally chosen image tag.
Its sid base is pinned to the amd64 manifest digest; its apt repository is moving, so retain `dpkg-query -W` with each build.
It installs LLVM, Clang and LLD 21 and the packaging and Lean Code prerequisites.
Use a disposable container limited to four CPUs and a four-CPU affinity mask, with persistent SSD scratch owned by the build user.
Keep enough space for the source, generated C bootstrap, self-hosted compiler and package staging.

`fetch-source.sh NEW_DIRECTORY` makes a full clone and verifies the pinned commit against origin/main.
It refuses an existing destination; `fetch-source.sh --verify DIRECTORY` verifies an existing clone without changing it.
Inside the toolchain container, `prepare-source.sh VERIFIED_CLONE NEW_OUTPUT_DIRECTORY` creates the original source archive and the Lean-integrated `.dsc` at `0.16.0+cgm.0399d2b19b-1+lc1`.
Extract the `.dsc` using `dpkg-source -x`, then build with `dpkg-buildpackage -us -uc -b -j4` as the build user.
Set `SPARKY_LC_ARCHIVE_CONFIG` and `SPARKY_LC_SCRATCH` for the automatic link gate, as the edition's Lean Code archive documentation describes.
The isolated link gate needs bubblewrap user namespaces available inside the container. With Docker, use `--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined`; the last option permits the nested `/proc` mount. Check a bubblewrap `/bin/true` probe with these options before the build. Before staging, run `PYTHONPATH=sparky-os python3 -m lean.release check-identity` on every resulting `.deb`; the toolkit must carry its released 0.1.24 identity.

The source package retains the edition's exact Lean toolkit and provenance helper.
Lean Code 0.1.24 projects C/C++ before the CMake bootstrap. That bootstrap builds a full compiler from the pinned source and its upstream WASM seed: the intermediate `zig2` has neither `version` nor `ast-check`. The recipe keeps the full compiler under `build/consumer`, restores the authored inputs, and qualifies C/C++ and Zig together with `LEAN_ZIG=build/consumer/bin/zig`. That same compiler then builds the final stage3 from the projected source, using the checked CMake-generated flags. This avoids a dependency on a previously installed cgm-zig package. Installed sources are restored before the separate payload projection. The retained payload map identifies `/usr/lib/cgm-zig/lib/zig` as source `lib/`, so authored recovery uses the exact source path instead of inferring it from installed bytes. Upstream deliberately creates empty `*test.zig` placeholders. Preparation declares `/usr/lib/cgm-zig/lib/zig/*test.zig` as generated `empty` outputs through `lean.debian_prepare`; payload restoration checks that exact form and records each match. A nonempty placeholder or a declaration matching no installed file stops the build.
The root test corpus is retained because its deliberately invalid source and comment directives are test inputs.
Zig qualification uses the bootstrap compiler’s tokenizer and ast-check; the retained language plan selects C and Zig. The bootstrap reads authored Zig to establish that consumer; only the subsequent stage3 compiler and projected library are packaged. The unversioned `clang` dependency supplies the raw lexer used for conditional C headers.
No toolkit source is changed by this recipe.

The fork's [build notes](https://github.com/danielcamposramos/cgm-zig/blob/0399d2b19b71ed865cc2e6d5e21224f124e373db/docs/crown/BUILDING.md) require `RelWithDebInfo`, `ZIG_RELEASE_SAFE=ON` and `-Ddebug-extensions` together.
`configure.sh` checks the actual generated stage3 command; `CMAKE_BUILD_TYPE=ReleaseSafe` alone selects ReleaseFast plus stripping and is rejected.
The baseline CPU target follows Ubuntu's packaging, avoiding a dependency on the build station's instruction set.
The source package supplies the Debian amd64 libc include and CRT paths through `ZIG_LIBC`, uses build-local Zig caches, and retains compiler symbols for diagnostics. Like Ubuntu zig0.16, installation removes the toolchain RUNPATH with `chrpath -d`, so dpkg resolves LLVM and Clang through their runtime packages in the standard library directory.

## Installed layout

The compiler is `/usr/lib/cgm-zig/bin/zig`; its matching library is `/usr/lib/cgm-zig/lib/zig`.
This preserves upstream's executable-relative library lookup.
The package provides `zig` and registers `/usr/bin/zig` through update-alternatives at priority 2147483647, the highest update-alternatives accepts: the edition's zig is the zig whenever another one is installed too (Daniel, 2026-11-02, ORDER 361), and a choice the person makes with `update-alternatives --config zig` stays theirs.
The Debian Zig Team's `zig` package (zig-defaults, built by Ubuntu) owns `/usr/bin/zig` directly instead of joining the alternatives group, so the preinst diverts every other package's `/usr/bin/zig` to `/usr/bin/zig.distrib` (moving one already installed aside); that compiler stays reachable by its own name (`zig0.16`). The postrm removes the diversion and gives the file its name back.
`tests/alternatives.sh` installs it with the Debian Zig Team's zig in both orders and removes each.

`tests/installed.sh NEW_SCRATCH_DIRECTORY` checks the installed version, hello world, and a C caller of a Zig shared library in a clean container.
Alternatives lifecycle, downstream engine, apt resolution and publication link-gate proofs remain required in addition to that test.

See [ATTRIBUTIONS.md](ATTRIBUTIONS.md) for the compiler, fork, Debian/Ubuntu packaging and SparkyLinux credits.
