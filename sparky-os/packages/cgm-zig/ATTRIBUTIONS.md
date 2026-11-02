# Attributions

## Zig

The compiler and standard library are the work of the Zig project, Andrew Kelley and the Zig contributors.
The pinned source's [README.upstream.md](https://github.com/danielcamposramos/cgm-zig/blob/0399d2b19b71ed865cc2e6d5e21224f124e373db/README.upstream.md) identifies Andrew Kelley's project role, the CMake bootstrap and the executable-relative standard-library search.
Its [LICENSE](https://github.com/danielcamposramos/cgm-zig/blob/0399d2b19b71ed865cc2e6d5e21224f124e373db/LICENSE) names the Zig contributors and grants the MIT (Expat) licence.
Bundled third-party sources have their own notices, which must be retained in the source and package copyright inventory.
The package must not describe every vendored file as MIT.
Zig's [package-maintainer guidance](https://ziglang.org/learn/overview/#friendly-toward-package-maintainers) describes its C/C++ and LLVM bootstrap and system integration facilities.

## cgm-zig

Daniel Campos Ramos maintains this fork in his own account.
The fork's [PROVENANCE.md](https://github.com/danielcamposramos/cgm-zig/blob/0399d2b19b71ed865cc2e6d5e21224f124e373db/PROVENANCE.md) records Daniel's direction and the compiler work of Claude Fable, Claude Opus, Claude Sonnet, Claude Haiku and GPT 6 Astra.
This package carries that compiler; packaging does not transfer authorship of its fixes.
The ReleaseSafe and multiarch libc requirements come from the fork's [BUILDING.md](https://github.com/danielcamposramos/cgm-zig/blob/0399d2b19b71ed865cc2e6d5e21224f124e373db/docs/crown/BUILDING.md).

## Debian and Ubuntu packaging

Ubuntu's [zig0.16 source packaging](https://archive.ubuntu.com/ubuntu/pool/universe/z/zig0.16/zig0.16_0.16.0~us1-0ubuntu1.debian.tar.xz) names nick black and Nick Hastings in its packaging copyright, and Pushkar Kulkarni in its Ubuntu changelog.
This recipe follows its `ZIG_TARGET_MCPU=baseline` choice and uses its LLVM 21 development-package list as a reference.
Its CMake build and stage3 library layout agree with the fork's upstream build notes.
Its `chrpath -d` install step fixes the same measured LLVM dependency-lookup error here: the compiler must use the standard runtime library directory, not the toolchain development-directory alias.
The recipe scripts are new; Ubuntu's rules are reference material, not copied wholesale.
The detailed Debian copyright inventory is adapted from Ubuntu's zig0.16 package, with its legal texts retained and entries for the fork's retained Clang resource headers and the edition's packaging.
Ubuntu's [zig-defaults 5ubuntu1](https://archive.ubuntu.com/ubuntu/pool/universe/z/zig-defaults/zig-defaults_5ubuntu1.tar.xz) chooses zig0.16 with a directly owned `/usr/bin/zig` link.
This package instead follows the edition's alternatives design.
Coexistence requires another provider to participate in the same alternatives group; a package owning `/usr/bin/zig` directly is not proven compatible.
The Debian dpkg maintainers document registration and removal in [update-alternatives(1)](https://manpages.debian.org/testing/dpkg/update-alternatives.1.en.html).

## Edition packaging

Sparky Stereo OS is Daniel Ramos's (Capitain Jack) edition of SparkyLinux, created by Paweł "pavroo" Pijanowski.
The recipe follows the edition's [packaging skill](https://github.com/Sparky-OS/sparky-stereo-os/blob/main/skills/edition-packaging/SKILL.md) and credits Paweł's package formula.
Daniel specifies the package design; GPT 6 Astra via Codex assists with source research and build preparation.
New recipe scripts are licensed under GPL-3.0-or-later; the compiler retains its upstream licences.
