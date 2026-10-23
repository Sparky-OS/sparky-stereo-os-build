#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Proves the edition's linux-libc-dev (kernel/lean/libc-dev.py) in a clean Debian forky amd64 container (ORDER 222):
#   1. control: with Debian's linux-libc-dev, a program that includes <drm/drm_mode.h> and uses struct drm_hdmi_3d_metadata does not compile
#      (libdrm-dev ships copies of drm.h and drm_mode.h of its own in /usr/include/libdrm: a program that includes those sees libdrm'"'"'s sync, not
#      the kernel package; the script prints whether libdrm'"'"'s copy has the structure);
#   2. our package upgrades Debian's cleanly and the same program compiles and sees the structure (size and field offsets);
#   3. i386 multiarch: libc6-dev:i386 and a -m32 build still work, no second linux-libc-dev appears (arch all, Multi-Arch: foreign);
#   4. the layout is Debian's: every path Debian's 7.2.11-1 package has, ours has, but the headers 7.3 removed or added.
#
#   kernel/tests/libc-dev-proof.sh LINUX-LIBC-DEV.deb IMAGE
# IMAGE is a Debian forky amd64 image with apt sources (for example sparky-lc-final-install-amd64:20261021). Prints the log; exit status 1 on any failure.
set -eu
DEB=$(readlink -f "${1:?usage: libc-dev-proof.sh linux-libc-dev.deb image}")
IMAGE=${2:?image}
docker run --rm --platform linux/amd64 -v "$DEB":/proof/ours.deb:ro "$IMAGE" sh -eu -c '
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1
apt-get -y -qq --no-install-recommends install gcc libdrm-dev >/dev/null 2>&1
cat > /proof/t.c <<"EOC"
#include <stddef.h>
#include <stdio.h>
#include <drm/drm_mode.h>
int main(void)
{
	struct drm_hdmi_3d_metadata m;
	printf("sizeof=%zu type@%zu length@%zu data@%zu\n", sizeof m, offsetof(struct drm_hdmi_3d_metadata, type),
	       offsetof(struct drm_hdmi_3d_metadata, length), offsetof(struct drm_hdmi_3d_metadata, data));
	return 0;
}
EOC
echo "libdrm-dev $(dpkg-query -W -f="\${Version}" libdrm-dev) own drm_mode.h mentions drm_hdmi_3d_metadata: $(grep -c drm_hdmi_3d_metadata /usr/include/libdrm/drm_mode.h)"
echo "== 1. control: Debian linux-libc-dev $(dpkg-query -W -f="\${Version}" linux-libc-dev)"
if gcc /proof/t.c -o /proof/t 2>/proof/control.err; then echo "FAIL: compiled against Debian headers"; exit 1; fi
head -n 2 /proof/control.err
echo "== 2. ours over Debian"
dpkg -i /proof/ours.deb >/dev/null
echo "installed: $(dpkg-query -W -f="\${Version} \${Architecture} \${Multi-Arch}" linux-libc-dev)"
dpkg --audit; echo "dpkg --audit: empty above means clean"
gcc /proof/t.c -o /proof/t && /proof/t
test "$(/proof/t)" = "sizeof=32 type@0 length@1 data@2" || { echo "FAIL: unexpected layout"; exit 1; }
apt-get -s dist-upgrade | grep -E "^(Inst|Remv|Conf) .*(linux-libc|libc6)|^Remv" && { echo "FAIL: apt wants to touch linux-libc-dev, libc6 or remove something"; exit 1; } || echo "apt-get -s dist-upgrade: does not touch linux-libc-dev or libc6, removes nothing"
echo "== 3. i386 multiarch"
dpkg --add-architecture i386
apt-get update -qq >/dev/null 2>&1
apt-get -y -qq --no-install-recommends install libc6-dev:i386 gcc-multilib >/dev/null 2>&1
dpkg -l | grep -E "linux-libc-dev|libc6-dev" | awk "{print \$1,\$2,\$3,\$4}"
test "$(dpkg -l | grep -c " linux-libc-dev")" = 1 || { echo "FAIL: more than one linux-libc-dev"; exit 1; }
test "$(dpkg-query -W -f="\${Version}" linux-libc-dev)" = "$(dpkg-deb -f /proof/ours.deb Version)" || { echo "FAIL: version changed"; exit 1; }
cat > /proof/t32.c <<"EOC"
#include <stdio.h>
#include <drm/drm_mode.h>
#include <asm/unistd.h>
int main(void) { printf("m32 sizeof=%zu NR_write=%d\n", sizeof(struct drm_hdmi_3d_metadata), __NR_write); return 0; }
EOC
gcc -m32 /proof/t32.c -o /proof/t32 && /proof/t32
dpkg --audit; apt-get -s dist-upgrade | grep -E "^(Inst|Remv|Conf) .*(linux-libc|libc6)|^Remv" && { echo "FAIL: apt wants to touch linux-libc-dev, libc6 or remove something"; exit 1; } || echo "apt-get -s dist-upgrade: does not touch linux-libc-dev or libc6, removes nothing"
echo "== 4. layout against Debian 7.2.11-1"
dpkg -L linux-libc-dev | grep -v "^/usr/share" | sort > /proof/ours.lst
cd /proof && apt-get download linux-libc-dev=7.2.11-1 >/dev/null 2>&1 && dpkg-deb -c linux-libc-dev_7.2.11-1_all.deb | awk "{print \$6}" | sed "s,^\.,," | grep -v "^/usr/share" | sed "s,/\$,," | grep -v "^$" | sort > /proof/deb.lst
sed "s,/\$,," /proof/ours.lst | sort > /proof/ours2.lst
echo "only in Debian 7.2.11:"; comm -23 /proof/deb.lst /proof/ours2.lst
echo "only in ours:"; comm -13 /proof/deb.lst /proof/ours2.lst
'
