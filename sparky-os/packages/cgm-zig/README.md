# cgm-zig package preparation

This recipe prepares the pinned cgm-zig source and the Debian sid amd64 compiler build environment.
The Debian package assembly and installed-package proofs are not implemented yet.

The source remains in [Daniel Campos Ramos's repository](https://github.com/danielcamposramos/cgm-zig).
`source.env` pins commit `0399d2b19b71ed865cc2e6d5e21224f124e373db` and compiler version `0.16.0+cgm.0399d2b19b`.
`fetch-source.sh NEW_DIRECTORY` makes a full clone, checks that the commit belongs to `origin/main`, and checks out that commit detached.
It refuses an existing destination rather than overwriting work.
`fetch-source.sh --verify DIRECTORY` checks a previously fetched source without changing it.

Build the Dockerfile as a lane-owned image with `--platform linux/amd64`.
Its Debian sid base is pinned to the amd64 manifest digest, and it installs LLVM, Clang and LLD 21 development libraries.
Record the installed dependency versions for every build: the base digest does not pin the moving sid apt repository.
Run `configure.sh SOURCE EMPTY_BUILD_DIRECTORY` inside that image, as the build user's uid, with the source and scratch on SSD storage.
Limit the container to four CPUs and use `ninja -j4` for the eventual compile.
The configure step checks the generated stage3 invocation before any compilation.

The fork's [build notes](https://github.com/danielcamposramos/cgm-zig/blob/0399d2b19b71ed865cc2e6d5e21224f124e373db/docs/crown/BUILDING.md) require `RelWithDebInfo`, `ZIG_RELEASE_SAFE=ON` and `-Ddebug-extensions` together.
A CMake build type called `ReleaseSafe` alone selects a stripped ReleaseFast stage3 and is rejected by the command check.
The baseline CPU target follows Ubuntu's Zig packaging so the package does not require the build station's instruction set.
The build will need an explicit `ZIG_LIBC` file with `include_dir=/usr/include`, `sys_include_dir=/usr/include/x86_64-linux-gnu`, and the detected CRT directories.
Set both Zig cache directories to persistent lane scratch, before compiling.

Before compilation, the disposable source must pass the edition's Lean Code source preparation.
Keep `.zig` files authored until a Zig adapter is available, and record that coverage gap for a subsequent rebuild.
Do not alter the shared Lean toolkit in this recipe.
The eventual package layout is `/usr/lib/cgm-zig/bin/zig` plus `/usr/lib/cgm-zig/lib/zig`, preserving the upstream executable-relative library search.
`/usr/bin/zig` will be registered through `update-alternatives`, with `Provides: zig` in package metadata.

See [ATTRIBUTIONS.md](ATTRIBUTIONS.md) for upstream and packaging references.
