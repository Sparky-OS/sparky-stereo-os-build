#!/bin/bash
set -euo pipefail
export LC_ALL=C DEB_BUILD_OPTIONS='parallel=2 nocheck' CARGO_NET_OFFLINE=true
export SOURCE_DATE_EPOCH=1794523022
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
cd /work/tree
test "$(dpkg-query -W -f='${Version}' rustc)" = 1.98.1+dfsg1-1+stereo3d1+lc1
make -f debian/rules debian/dh_auto_configure.stamp
python3 /scripts/measure.py /work/check-metrics python3 src/bootstrap/bootstrap.py check --stage 1 --config debian/config.toml -j2 compiler library src/tools/rustfmt src/tools/clippy src/tools/rust-analyzer

python3 /scripts/measure.py /work/tools-metrics python3 src/bootstrap/bootstrap.py build --stage 0 --config debian/config.toml -j2 src/tools/cargo src/tools/wasm-component-ld
