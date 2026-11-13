#!/bin/bash
set -euo pipefail
export LC_ALL=C CARGO_NET_OFFLINE=true DEB_BUILD_OPTIONS='parallel=2 nocheck' SOURCE_DATE_EPOCH=1794523022
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
export CC=cc CXX=c++ AR=ar RANLIB="ar s"
export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER=x86_64-linux-gnu-gcc
cd /work/tree
python3 /scripts/measure.py /work/tools-metrics make -f debian/rules debian/dh_auto_build.stamp 'RUSTBUILD_FLAGS=--stage 1 --config debian/config.toml --on-fail env library src/tools/cargo src/tools/rustfmt src/tools/clippy src/tools/rust-analyzer src/tools/wasm-component-ld src/librustdoc'
