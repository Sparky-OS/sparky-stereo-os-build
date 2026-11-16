#!/bin/bash
# Makes the orig archive of scx-scheds: sched-ext/scx at the tag v1.1.4 (the tag CachyOS packages, CachyOS-PKGBUILDS scx/scx-scheds PKGBUILD, 0c7ddbc13573),
# with its crates vendored by `cargo vendor --locked`, so the build needs no network (Debian Policy 4.9: the build does not reach the network).
# Needs git, gpg, cargo and network; run it where the build's own cargo is installed. Byte for byte the same each time: git archive of the commit (its
# time is the archive's), the vendor folder as cargo wrote it, sorted names, one xz thread.
# The tag is checked first: its signature must be Tejun Heo's (key 697C63013E65270255EBC2608744DC1EB26B5A9A or one of the keys CachyOS lists), and
# its commit must be e7b3a219617472cf78880ac424714e52c932db61.
# Usage: make-orig.sh OUTDIR
set -euo pipefail
OUT=${1:?output folder}; COMMIT=e7b3a219617472cf78880ac424714e52c932db61
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
export GNUPGHOME=$W/gnupg; mkdir -m 700 "$GNUPGHOME"
for k in 697C63013E65270255EBC2608744DC1EB26B5A9A F5504C7B7B8107B40EF9E97AA1148BB3207BCC33 A8775C60262EEF2AA34A864F5DAD005C4BFEA770 EE2B8DAB1F6D1AA9DD1A4475AD851C1B71DF8FBF 49F2D1CB86447DFD1F14B27A8B61A0894BDB3A92; do
	gpg --batch --quiet --keyserver hkps://keys.openpgp.org --recv-keys "$k" || true
done
git clone -q --depth 1 --branch v1.1.4 https://github.com/sched-ext/scx.git "$W/scx"
git -C "$W/scx" fetch -q --depth 1 origin tag v1.1.4
git -C "$W/scx" tag -v v1.1.4 2>&1 | grep -q 'Good signature\|Assinatura válida' || { echo 'the tag v1.1.4 has no valid signature from a known key' >&2; exit 1; }
[ "$(git -C "$W/scx" rev-parse --verify "v1.1.4^{commit}")" = "$COMMIT" ]
mkdir -p "$W/tree"; git -C "$W/scx" archive --format=tar --prefix=scx-scheds-1.1.4+ds/ "$COMMIT" | tar -x -C "$W/tree"
cd "$W/tree/scx-scheds-1.1.4+ds"
mkdir -p .cargo; cargo vendor --locked vendor >.cargo/config.toml
mkdir -p "$OUT"
TIME=$(git -C "$W/scx" log -1 --format=%ct "$COMMIT")
(cd "$W/tree" && tar --sort=name --mtime="@$TIME" --owner=0 --group=0 --numeric-owner -cf - scx-scheds-1.1.4+ds) | xz -6 -T1 >"$OUT/scx-scheds_1.1.4+ds.orig.tar.xz"
sha256sum "$OUT/scx-scheds_1.1.4+ds.orig.tar.xz"; du -sm "$W/tree/scx-scheds-1.1.4+ds/vendor" | cut -f1 | sed 's/$/ MiB vendored/'
