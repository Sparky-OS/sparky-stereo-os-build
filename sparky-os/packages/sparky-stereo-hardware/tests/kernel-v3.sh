#!/bin/bash
# The x86-64-v3 kernel by detection (ORDER 108), what a fixture cannot show, in an amd64 debian:testing container:
#  1. which kernel GRUB lists first: grub-mkconfig_lib's own version_test_gt and linux-version, on the release names of the edition's three
#     flavours (the base and v3 releases of one build, and a newer base build);
#  2. the two package names exist in the published tree (apt-cache policy), installing them removes nothing and keeps the base kernel meta.
# Usage: kernel-v3.sh PUBLISHED_TREE (a repository tree with dists/, read only)
set -uo pipefail
TREE=${1:?published tree}
IMAGE=${IMAGE:-gr108-base:testing-20261027}
docker run --rm --cpus 2 --ulimit core=1 --name gr108-kv3 -e DEBIAN_FRONTEND=noninteractive \
	-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v /K3D/partners/https-only-apt.sh:/run/https-only-apt.sh:ro -v "$TREE:/tree:ro" "$IMAGE" bash -c '
failed=0
ok() { echo "PASS $*"; }; bad() { echo "FAIL $*"; failed=1; }
sh /run/https-only-apt.sh >/dev/null; apt-get -y update >/dev/null 2>&1; apt-get -y install grub-common linux-base >/dev/null 2>&1 || { echo "FAIL setup"; exit 1; }
pkgdatadir=/usr/share/grub; . /usr/share/grub/grub-mkconfig_lib
# /etc/grub.d/10_linux: reverse_sorted_list=$(echo $list | tr " " "\n" | sed -e "s/\.old$/ 1/; / 1$/! s/$/ 2/" | version_sort -r | ...), the first one is the default entry
latest() { printf "%s\n" "$@" | sed -e "s/\.old$/ 1/; / 1$/! s/$/ 2/" | version_sort -r | sed -e "s/ 1$/.old/; s/ 2$//" | head -n1; }
b=7.3.1-stereo3d16; v=7.3.1-stereo3d16-v3; r=7.3.1-rt-stereo3d16
[ "$(latest $b $v $r)" = $v ] && ok "GRUB (10_linux: version_sort -r of grub-mkconfig_lib) puts $v first of $b $v $r" || bad "GRUB first: $(latest $b $v $r)"
[ "$(linux-version sort --reverse $b $v $r | head -n1)" = $v ] && ok "linux-version sort --reverse agrees" || bad "linux-version order"
[ "$(latest $b 7.3.1-stereo3d17 $v)" = 7.3.1-stereo3d17 ] && ok "a newer base build (stereo3d17) is listed before the older v3 one: the newest build boots first, so a round that builds the flavours together (one -b number) keeps v3 on top" || bad "newer base"
[ "$(latest $b 7.3.1-stereo3d17 $v 7.3.1-stereo3d17-v3)" = 7.3.1-stereo3d17-v3 ] && ok "with both flavours of build 17, v3 is first" || bad "build 17 order"
echo "deb [trusted=yes] file:/tree mashtabba main" >/etc/apt/sources.list.d/tree.list
apt-get -y update >/dev/null 2>&1
for p in linux-image-sparky-stereo-v3 linux-headers-sparky-stereo-v3 linux-image-sparky-stereo; do
	c=$(apt-cache policy $p | sed -n "s/^  Candidate: //p"); [ -n "$c" ] && [ "$c" != "(none)" ] && ok "$p has a candidate: $c" || bad "$p has no candidate"
done
apt-get -s install linux-image-sparky-stereo linux-image-sparky-stereo-v3 linux-headers-sparky-stereo-v3 >/tmp/sim.out 2>&1; echo "simulation exit $?"
grep -q "^Remv" /tmp/sim.out && bad "installing the v3 kernel removes something: $(grep ^Remv /tmp/sim.out | head -3)" || ok "installing the v3 kernel beside the base kernel meta removes nothing"
grep "^Inst linux-" /tmp/sim.out | cut -c1-110
grep -q "^Inst linux-image-.*-v3 " /tmp/sim.out && grep -q "^Inst linux-image-[0-9.]*-stereo3d[0-9]* " /tmp/sim.out && ok "both the base and the v3 kernel image are installed together" || bad "not both images"
exit $failed'
