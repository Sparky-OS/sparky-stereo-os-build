# rustc: the edition's Rust toolchain

The edition builds its own Rust compiler, cargo and standard library from source, on Debian's `rustc` source package.
Debian's packaging stays as Debian has it; the recipe adds one binary package and builds through Lean Code.

## What the recipe makes

- Every binary package of Debian's `rustc` source, under Debian's names (`rustc`, `cargo`, `libstd-rust-N.NN`, `libstd-rust-dev`, `rust-src`, `rust-clippy`, `rustfmt`, `rust-analyzer`, `rust-doc`, `cargo-doc`, `rust-gdb`, `rust-lldb`, `rust-llvm`, `rust-all`, and the wasm32 and bpf standard libraries), at Debian's version plus `+stereo3dN+lc1`.
- `libstd-rust-HASH`: the standard library's shared object, `libstd-HASH.so`, in the public library folder.
  Debian's rules delete that file, so a program built with `-C prefer-dynamic` has nothing to load on Debian.
  The package is named after the library's own name, as Debian Policy 8.1 asks ("The run-time shared library must be placed in a package whose name changes whenever the SONAME of the shared library changes"), so the libraries of two compilers install side by side.
  `libstd-rust-dev` depends on it and keeps a link to it in the sysroot, where rustc looks for it.
  It ships a `symbols` file with an exact dependency, so `dpkg-shlibdeps` writes `libstd-rust-HASH (= VERSION)` into every program that needs it.

## The chain

No compiler binary is downloaded.
The seed is the compiler Debian's archive has, as Debian's `README.source` prescribes ("The system rustc has to be either the previous or the same version as the rustc being built"), and each link builds the next:

1. `versions/1.98.1.env`: Debian's 1.98.1 source, built by Debian testing's rustc 1.97.1.
2. `versions/1.99.1.env`: Debian's 1.99.1 source, built by our own 1.98.1 (the fourth argument of `build.sh`).

A link whose seed is ours stops when the candidate for `rustc` is not ours: it never takes Debian's compiler behind the recipe's back.
The compile runs in a container without network.

## Building

```sh
# Debian's source package, in a new empty folder (a container with https-only apt and deb-src lines for the suite)
apt-get source --download-only rustc=1.98.1+dfsg1-1
# the recipe: versions file, an empty work folder on a disk with 60 GB free, the source folder, the seed's packages
BASE_IMAGE=<debian testing, amd64, by digest> bash build.sh versions/1.98.1.env WORK SRC
BASE_IMAGE=<the same> bash build.sh versions/1.99.1.env WORK2 SRC2 WORK/out
```

`WORK/out` holds the archives, the `+lc1` source package and `SHA256SUMS`; `WORK/build.log` is the build's own log.
The build runs with `nocheck`: the compiler's test suite is not part of this recipe's build; set `SPARKY_RUSTC_BUILD_OPTIONS=` to run it.
The disk guard samples the work folder's disk every 5 s and kills the build 1 GiB above `SPARKY_DISK_FLOOR_GIB` (12 by default).

## The first build of a version

The runtime package's name holds 16 hex digits that rustc gives the standard library when it builds it.
They come from the compiler's version, its commit and the LLVM it links, so they are known only after a build.
A new versions file therefore says `STD_HASH=discover`.
That build compiles everything, stops at the install step with the library's real name, makes the source package again with it and packages the tree it has already compiled (`dpkg-buildpackage -nc`), without compiling twice.
It prints the value to record: put `STD_HASH=<the 16 digits>` in the versions file and commit it.
From then on the source package is made in one pass, and a build whose library has another name stops and says so.

## Lean Code

`lean.debian_prepare` adds the Lean Code stages to Debian's rules.
The compiler's native inputs are the seven C++ files of `compiler/rustc_llvm/llvm-wrapper`; they go through the C and C++ pass before compilation.
The other C-family files of the tree are kept as authored by the preserve plan, each group with the consumer that reads it: vendored crates (their `.cargo-checksum.json` binds every file's bytes), the standard library's sources shipped in `rust-src`, test fixtures, benchmark inputs.
The compiler's own Rust sources are not projected yet: that needs the Rust adapter of lean 0.1.29 under a language plan, and a compiler build to qualify it.
The link and start gate (`python3 -m lean.release check-link`) runs on `WORK/out` after the build, because inside the build the new compiler's packages are not installable yet.

## Credits

Debian's rustc packaging is the work of the Debian Rust Maintainers; the uploaders named in `debian/control` are Ximin Luo, Sylvestre Ledru and Fabian Grünbichler.
The compiler is the Rust project's.
