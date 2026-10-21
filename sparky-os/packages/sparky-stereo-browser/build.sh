#!/bin/bash
# SPDX-License-Identifier: MPL-2.0
set -eo pipefail
: "${SPARKY_BROWSER_TOOLCHAIN_ROOT:?Supply the pinned compiler bundle}"
source debian/browser-build.env
export MOZ_BUILD_DATE MOZ_SOURCE_REPO MOZ_SOURCE_CHANGESET MOZCONFIG="$PWD/debian/mozconfig"
export MOZBUILD_STATE_PATH="$PWD/debian/mozbuild-state"
export CARGO_HOME="$PWD/debian/cargo-home" CARGO_NET_OFFLINE=true
export MOZ_NOSPAM=1 MACH_MAIN_PID=0
export RUSTC="$SPARKY_BROWSER_TOOLCHAIN_ROOT/.rustup/toolchains/1.98.1-x86_64-unknown-linux-gnu/bin/rustc"
export CARGO="$SPARKY_BROWSER_TOOLCHAIN_ROOT/.rustup/toolchains/1.98.1-x86_64-unknown-linux-gnu/bin/cargo"
export CBINDGEN="$SPARKY_BROWSER_TOOLCHAIN_ROOT/.mozbuild/cbindgen/cbindgen"
export NASM="$SPARKY_BROWSER_TOOLCHAIN_ROOT/.mozbuild/nasm/nasm"
export NODEJS="$SPARKY_BROWSER_TOOLCHAIN_ROOT/.mozbuild/node/bin/node"
export DUMP_SYMS="$SPARKY_BROWSER_TOOLCHAIN_ROOT/.mozbuild/dump_syms/dump_syms"
export PKG_CONFIG="$SPARKY_BROWSER_TOOLCHAIN_ROOT/.mozbuild/pkgconf/pkg-config"
export PATH="$(dirname "$RUSTC"):$SPARKY_BROWSER_TOOLCHAIN_ROOT/.mozbuild/clang-22/bin:$PATH"
# Retain the accepted release profile instead of importing Debian's unrelated
# generic optimisation flags into the browser's own build configuration.
unset CFLAGS CXXFLAGS CPPFLAGS LDFLAGS
case "$1" in
configure) ./mach configure ;;
build) ./mach build ;;
package)
    ./mach package
    ./mach package-multi-locale --locales en-US pl pt-BR fr ja ko zh-CN zh-TW
    ;;
*) exit 2 ;;
esac
