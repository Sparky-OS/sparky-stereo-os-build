#!/bin/sh
# Proves the kernel configuration without building a kernel: runs configure.sh (the
# configuration part of build-deb.sh) in a debian:testing container, on a read-only mount of
# the kernel tree with O= pointing at a scratch folder, and checks the six options the
# configuration must carry in the resulting .config. The base is the running kernel's config.
#
#   kernel/tests/config-proof.sh [configure-script] [out-dir]
#
# The configure script defaults to ../configure.sh; give an older one to see the test fail on
# it. out-dir (default /K3D/temp/partners/queue/gaming-rig-steps/work/config-proof) keeps the
# resulting .config as out-dir/kbuild/.config and the base as out-dir/base.config.
# Uses 2 threads; no kernel is built.
set -eu
HERE=$(cd "$(dirname "$0")/.." && pwd)
SRC=${SRC:-$HERE/../linux}
CFGSH=$(cd "$(dirname "${1:-$HERE/configure.sh}")" && pwd)/$(basename "${1:-$HERE/configure.sh}")
OUT=${2:-/K3D/temp/partners/queue/gaming-rig-steps/work/config-proof}
CONFIG=${CONFIG:-/boot/config-$(uname -r)}
mkdir -p "$OUT"
rm -rf "$OUT/kbuild"
cp "$CONFIG" "$OUT/base.config"
docker run --rm -e OWNER="$(id -u):$(id -g)" -v "$SRC":/src:ro -v "$OUT":/out -v "$CFGSH":/configure.sh:ro debian:testing sh -euc '
export DEBIAN_FRONTEND=noninteractive LC_ALL=C
trap "chown -R $OWNER /out" EXIT   # the scratch folder stays the caller-owned
apt-get update -qq
apt-get install -y -qq --no-install-recommends build-essential bc bison flex libssl-dev libelf-dev dwarves >/dev/null
cd /src
sh /configure.sh /out/base.config /out/kbuild
' >"$OUT/configure.log" 2>&1 || { tail -20 "$OUT/configure.log"; echo "FAIL: configure.sh did not run"; exit 2; }
rc=0
for o in SCHED_CLASS_EXT=y DEBUG_INFO_BTF=y RTW89_8852AU=m RTW89_8852CU=m RTW89_8922AU=m RTW89_8922DE=m; do
	if grep -q "^CONFIG_$o\$" "$OUT/kbuild/.config"; then echo "ok   CONFIG_$o"
	else echo "FAIL CONFIG_$o: $(grep -E "^(# )?CONFIG_${o%=*}[= ]" "$OUT/kbuild/.config")"; rc=1; fi
done
exit $rc
