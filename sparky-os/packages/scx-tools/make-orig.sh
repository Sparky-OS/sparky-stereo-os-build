#!/bin/bash
# Makes the orig archive of scx-tools: sched-ext/scx-loader at the tag v1.1.3 (the tag CachyOS packages, CachyOS-PKGBUILDS scx/scx-tools PKGBUILD) with its
# crates vendored by `cargo vendor --locked`. Needs git, cargo and network. The tag's commit must be eab0ea026f3f86879373b86ca64735b66719f6df. The tag is
# signed by key B1B70BB1CD56047DEF31DE2EB62C3D10C54D5DA9 (Vladislav Nepogodin), whose public key keys.openpgp.org holds without a user ID, so gpg cannot use
# it: the signature was NOT verified (2026-11-16); the commit id is checked against GitHub's tag and CachyOS's pin (its sha256 of the checkout).
# Usage: make-orig.sh OUTDIR
set -euo pipefail
OUT=${1:?output folder}; COMMIT=eab0ea026f3f86879373b86ca64735b66719f6df
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
git clone -q --depth 1 --branch v1.1.3 https://github.com/sched-ext/scx-loader.git "$W/loader"
[ "$(git -C "$W/loader" rev-parse --verify "v1.1.3^{commit}")" = "$COMMIT" ]
mkdir -p "$W/tree"; git -C "$W/loader" archive --format=tar --prefix=scx-tools-1.1.3+ds/ "$COMMIT" | tar -x -C "$W/tree"
cd "$W/tree/scx-tools-1.1.3+ds"
mkdir -p .cargo; cargo vendor --locked vendor >.cargo/config.toml
mkdir -p "$OUT"; TIME=$(git -C "$W/loader" log -1 --format=%ct "$COMMIT")
(cd "$W/tree" && tar --sort=name --mtime="@$TIME" --owner=0 --group=0 --numeric-owner -cf - scx-tools-1.1.3+ds) | xz -6 -T1 >"$OUT/scx-tools_1.1.3+ds.orig.tar.xz"
sha256sum "$OUT/scx-tools_1.1.3+ds.orig.tar.xz"; du -sm vendor | cut -f1 | sed 's/$/ MiB vendored/'
