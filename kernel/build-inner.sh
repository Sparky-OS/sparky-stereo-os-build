#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# The part of kernel/build-deb.sh that runs inside the build container, as the invoking user.
# Mounts: /work (empty work dir), /out (packages), /kernel (this directory, read-only), /series (patches, read-only),
# optionally /kernel-git (a git directory that has the tag). Environment: see build-deb.sh.
# Writes /out/exit-status (0 = all packages built and checked).
set -eu
st=1
trap 'echo $st > /out/exit-status' EXIT
fail() { echo "build-inner: FAIL: $*" >&2; exit 1; }
cd /work

echo "== tools: $(gcc --version | head -1) | $(rustc --version) | $(bindgen --version) | pahole $(pahole --version) | $(ld --version | head -1)"

echo "== source: $TAG"
if [ -n "${HAVE_KERNEL_GIT:-}" ]; then G=/kernel-git
else
    git clone --quiet --depth 1 --branch "$TAG" https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git /work/linux-git
    G=/work/linux-git
fi
got=$(git -C "$G" rev-parse "$TAG^{commit}")
[ "$got" = "$TAG_COMMIT" ] || fail "tag $TAG is $got, expected $TAG_COMMIT"
CT=$(git -C "$G" log -1 --format=%ct "$TAG^{commit}")
mkdir -p /work/src
git -C "$G" archive --format=tar "$TAG" | tar -x -C /work/src
[ -z "${HAVE_KERNEL_GIT:-}" ] && rm -rf /work/linux-git
cd /work/src

if [ "${SMOKE:-0}" = 1 ]; then
    # tests/package-smoke.sh: a tiny kernel through the same packaging, signing, BTF and headers steps (a few minutes), no series, no Debian configuration
    echo "== SMOKE: tinyconfig + tests/smoke.fragment, no patch series"
    make tinyconfig >/dev/null
    KCONFIG_CONFIG=.config scripts/kconfig/merge_config.sh -m .config /kernel/tests/smoke.fragment >/dev/null 2>&1
    make -s olddefconfig
    for o in MODULE_SIG_ALL DEBUG_INFO_BTF BLK_DEV_LOOP; do grep -q "^CONFIG_$o=[ym]" .config || fail "CONFIG_$o is not in the smoke configuration"; done
    cp .config "/out/config-$RELEASE"
else
echo "== series (flavour $FLAVOUR)"
sh /series/apply-series.sh /work/src "$FLAVOUR"

echo "== configuration"
sh /kernel/configure.sh "$FLAVOUR"
# the options this build exists for
for o in RUST DEBUG_INFO_BTF SCHED_CLASS_EXT MODULE_SIG_ALL SCHED_BORE; do
    grep -q "^CONFIG_$o=y" .config || fail "CONFIG_$o=y is not in the final configuration"
done
grep -q '^CONFIG_ANDROID_BINDER_IPC=m' .config || fail "binder is not a module"
[ "$FLAVOUR" != rt ] || grep -q '^CONFIG_PREEMPT_RT=y' .config || fail "rt flavour without PREEMPT_RT"
[ "$FLAVOUR" != v3 ] || grep -q '^CONFIG_X86_64_VERSION=3' .config || fail "v3 flavour without ISA level 3"
cp .config "/out/config-$RELEASE"
make rustavailable || fail "rustc / bindgen cannot build kernel Rust code"
fi

echo "== build (make -j$JOBS bindeb-pkg), release $RELEASE"
export KBUILD_BUILD_USER=sparky KBUILD_BUILD_HOST=stereo KBUILD_BUILD_TIMESTAMP="$(date -u -d "@$CT" '+%a %b %e %H:%M:%S UTC %Y')"
# the identity on the packages (Sparky Stereo OS packaging rule: never root@<container>); mkdebian reads these
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL='Capitain_Jack@yahoo.com'
# No "terse" in DEB_BUILD_OPTIONS: dpkg-buildpackage would append --no-print-directory to MAKEFLAGS after the "--" that separates the variables given
# on make's command line, and debian/rules then fails with "No rule to make target '--no-print-directory'". The quiet log comes from KBUILD_VERBOSE=0.
# (dpkg-buildpackage -j1, as scripts/Makefile.package calls it, leaves the parallel build to make's jobserver: -j$JOBS below.)
export DEB_BUILD_OPTIONS="parallel=$JOBS" KBUILD_VERBOSE=0
df -Pk /work | awk 'NR==2{printf "   free before: %d GB\n", $4/1048576}'
make -j"$JOBS" bindeb-pkg LOCALVERSION="$LV" KDEB_PKGVERSION="$PKGVER" KDEB_CHANGELOG_DIST=unstable \
    DPKG_FLAGS='-Ppkg.linux-upstream.nokerneldbg' >/work/make.log 2>&1 || { tail -40 /work/make.log; cp /work/make.log /out/make.log; fail "make bindeb-pkg"; }
cp /work/make.log /out/make.log
df -Pk /work | awk 'NR==2{printf "   free after:  %d GB\n", $4/1048576}'
REL=$(cat include/config/kernel.release)
[ "$REL" = "$RELEASE" ] || fail "kernel release is $REL, expected $RELEASE"

echo "== headers package: add the BTF-only vmlinux, .config and the header_postinst.d hooks (as Debian's linux-headers do)"
H=$(ls /work/linux-headers-"${RELEASE}"_*_amd64.deb)
rm -rf /work/hdr; dpkg-deb -R "$H" /work/hdr
D=/work/hdr/usr/src/linux-headers-$RELEASE
cp .config "$D/.config"
objcopy -j .BTF -j .BTF_ids vmlinux "$D/vmlinux"
chmod 644 "$D/vmlinux" "$D/.config"
readelf -S -W "$D/vmlinux" | grep -q ' \.BTF ' || fail "no .BTF in the headers' vmlinux"
sh /kernel/headers-postinst.sh "$RELEASE" > /work/hdr/DEBIAN/postinst
chmod 755 /work/hdr/DEBIAN/postinst
(cd /work/hdr && find . -type f ! -path './DEBIAN/*' -exec md5sum {} + | sed 's| \./| |' > DEBIAN/md5sums)
sz=$(du -sk /work/hdr --exclude=DEBIAN | cut -f1)
sed -i "s/^Installed-Size:.*/Installed-Size: $sz/" /work/hdr/DEBIAN/control
dpkg-deb --root-owner-group -b /work/hdr "$H.new" >/dev/null && mv "$H.new" "$H"

echo "== checks"
I=$(ls /work/linux-image-"${RELEASE}"_*_amd64.deb)
for deb in "$I" "$H"; do
    dpkg-deb -c "$deb" | grep -q 'signing_key' && fail "$deb contains the build signing key"
done
dpkg-deb -c "$I" | grep -q "boot/vmlinuz-$RELEASE" || fail "no vmlinuz in the image package"
# modules are signed: the signature marker ends the file (before xz, which compresses the signed module)
m=$(dpkg-deb -c "$I" | awk '{print $6}' | grep '\.ko\.xz$' | head -1)
[ -n "$m" ] || fail "no module in the image package"
dpkg-deb --fsys-tarfile "$I" | tar -xO "$m" | xz -dc | tail -c 28 | grep -q '~Module signature appended~' || fail "module $m is not signed"
dpkg-deb -c "$H" | grep -q "usr/src/linux-headers-$RELEASE/Module.symvers" || fail "no Module.symvers in the headers"
dpkg-deb -c "$H" | grep -q "usr/src/linux-headers-$RELEASE/vmlinux" || fail "no vmlinux in the headers"
# Debian's headers postinst since build 11 (headers-postinst.sh): linux-base's linux-run-hooks runs /etc/kernel/header_postinst.d
dpkg-deb --ctrl-tarfile "$H" | tar -xO ./postinst | grep -q '^linux-run-hooks headers postinst ' || fail "the headers package does not run the header_postinst.d hooks"

# the key that signed the modules must not outlive the build
for k in certs/signing_key.pem certs/signing_key.x509 certs/x509.genkey; do [ -f "$k" ] && shred -u "$k" 2>/dev/null || true; done

cp "$I" "$H" /out/
(cd /out && sha256sum linux-image-*.deb linux-headers-*.deb > SHA256SUMS && cat SHA256SUMS)
dpkg-deb -I "$I" | sed -n '1,12p'
ls -l /out
st=0
echo "== done: $RELEASE"
