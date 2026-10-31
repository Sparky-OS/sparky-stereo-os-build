#!/bin/bash
# Build an otherwise identical pair of internal libraries; these are test artifacts.
set -euo pipefail
SOURCE=$(realpath "${1:?Debian fwupd source tree}")
OUT=$(realpath -m "${2:?Fresh disposable output directory}")
HERE=$(cd "$(dirname "$0")" && pwd)
PATCH="$HERE/../../../sparky-os/packages/fwupd/preserve-external-mount.patch"
[[ ! -e "$OUT" ]] || { echo 'Output directory must not exist' >&2; exit 1; }
mkdir -p "$OUT"
cp -a "$SOURCE" "$OUT/source"
meson setup "$OUT/build" "$OUT/source" --prefix=/usr --libdir=lib/x86_64-linux-gnu \
    --auto-features=disabled -Dtests=false -Ddocs=disabled -Dman=false \
    -Dintrospection=disabled -Dbash_completion=false -Dfish_completion=false \
    -Dplugin_uefi_capsule_splash=false -Dgnutls=enabled -Dpolkit=enabled \
    -Dsystemd=disabled -Defi_os_dir=debian -Dsupported_build=enabled \
    -Dvendor_ids_dir=/usr/share/hwdata
ninja -C "$OUT/build" -j4 libfwupdplugin/libfwupdplugin.so
mkdir "$OUT/red-lib" "$OUT/green-lib"
cp -L "$OUT/build/libfwupdplugin/libfwupdplugin.so" "$OUT/red-lib/"
patch -d "$OUT/source" -p1 < "$PATCH"
ninja -C "$OUT/build" -j4 libfwupdplugin/libfwupdplugin.so
cp -L "$OUT/build/libfwupdplugin/libfwupdplugin.so" "$OUT/green-lib/"
sha256sum "$OUT/"{red-lib,green-lib}/libfwupdplugin.so
