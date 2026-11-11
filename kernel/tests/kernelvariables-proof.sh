#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# kernelvariables-proof.sh HEADERS_DEB [OUT]: red and green for series group 40 and kernel/lean/kernelvariables.sh (ORDER 311).
# In a fresh Debian testing container with what the headers depend on and no plain gcc command (gcc-16-for-host, make, kmod,
# libelf1t64, libssl3t64, pahole, libc6-dev): a small external module, built with kbuild as DKMS builds it,
#   red:   against the headers as the archive ships them (a package built before group 40): "gcc: not found";
#   green: against the same headers with group 40 applied to their Makefile and the .kernelvariables that stage.sh writes:
#          the module builds with x86_64-linux-gnu-gcc-N, with no compiler-version warning, and its vermagic names the release.
# A headers package built with group 40 needs no patching: the test then checks that it already carries both (green only).
set -euo pipefail
DEB=$(readlink -f "${1:?usage: kernelvariables-proof.sh HEADERS_DEB [OUT]}")
OUT=$(mkdir -p "${2:-$PWD/kernelvariables-proof}" && cd "${2:-$PWD/kernelvariables-proof}" && pwd)
HERE=$(cd "$(dirname "$0")/.." && pwd)
IMG=${IMG:-debian@sha256:fe4be93b807e7d05dccdaf54931173d9368b349f91a8170dadd787213aa3bf19}
docker run --rm --ulimit core=0 --platform linux/amd64 --cpus 2 -v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$(dirname "$(readlink -f "$0")")/../../tools/https-only-apt.sh":/run/https-only-apt.sh:ro -v "$DEB":/headers.deb:ro -v "$HERE":/kernel:ro -v "$OUT":/out "$IMG" bash -c '
set -euo pipefail
sh /run/https-only-apt.sh
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8
apt-get -qq update >/dev/null
apt-get -y -qq --no-install-recommends install gcc-16-for-host make kmod libelf1t64 libssl3t64 pahole libc6-dev bc patch >/out/00-apt.log 2>&1
! command -v gcc >/dev/null || { echo "FAIL: a plain gcc command is installed"; exit 1; }
dpkg-deb -x /headers.deb /
rel=$(ls /usr/src | sed -n "s/^linux-headers-//p")
K=/usr/src/linux-headers-$rel
mkdir -p /tmp/m && cd /tmp/m
printf "#include <linux/module.h>\n#include <linux/init.h>\nstatic int __init h_init(void) { return 0; }\nstatic void __exit h_exit(void) { }\nmodule_init(h_init);\nmodule_exit(h_exit);\nMODULE_LICENSE(\"GPL\");\n" >hello.c
echo "obj-m := hello.o" >Kbuild
build() { make -C "$K" M=/tmp/m V=1 modules >"/out/$1.log" 2>&1; }
if grep -q "^-include \$(objtree)/.kernelvariables$" "$K/Makefile" && [ -f "$K/.kernelvariables" ]; then
	echo "the package already carries group 40 and .kernelvariables: no red case" | tee /out/red.txt
else
	if build red; then echo "FAIL red: the module built without a gcc command"; exit 1; fi
	grep -q "gcc: not found" /out/red.log || { echo "FAIL red: another failure"; tail -5 /out/red.log; exit 1; }
	echo "PASS red: the shipped headers call plain gcc: $(grep -m1 "gcc: not found" /out/red.log)" | tee /out/red.txt
	for p in /kernel/series/40-debian-kernelvariables/*.patch; do (cd "$K" && patch -s -p1 <"$p"); done
	cc=$(sed -n "s/^CONFIG_CC_VERSION_TEXT=\"\(.*\)\"$/\1/p" "$K/.config")
	bash /kernel/lean/kernelvariables.sh "$rel" "$cc" >"$K/.kernelvariables"
	make -C /tmp/m -f /dev/null clean >/dev/null 2>&1 || true
	rm -f /tmp/m/*.o /tmp/m/*.ko /tmp/m/.*.cmd
fi
build green || { echo "FAIL green: the module did not build"; tail -10 /out/green.log; exit 1; }
grep -q "x86_64-linux-gnu-gcc-[0-9]" /out/green.log || { echo "FAIL green: not built with x86_64-linux-gnu-gcc-N"; exit 1; }
! grep -q "the compiler differs" /out/green.log || { echo "FAIL green: compiler-version warning"; exit 1; }
v=$(modinfo -F vermagic /tmp/m/hello.ko)
case "$v" in "$rel "*) ;; *) echo "FAIL green: vermagic $v"; exit 1 ;; esac
echo "PASS green: built with $(grep -o "x86_64-linux-gnu-gcc-[0-9]*" /out/green.log | sort -u | tr "\n" " ")no compiler warning; vermagic $v" | tee /out/green.txt
chown -R '"$(id -u):$(id -g)"' /out'
