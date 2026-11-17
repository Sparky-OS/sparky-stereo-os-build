#!/bin/bash
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/15
# Copyright 2026 under the GNU GPL3 License
# Builds sparky-backup-core-stereo, the edition's fork of SparkyLinux's sparky-backup-core
# (Sparky-OS/sparky-backup-core-stereo, folder 9), the way SparkyLinux packages its packer: the
# tool's folders laid into a DEBIAN tree (control in deb-package-builder's field order, md5sums,
# copyright under /usr/share/doc). It replaces sparky-backup-core and provides it, so packages
# that depend on the packer keep working; plain sparkybackup behaves as SparkyLinux's.
# Run it inside a debian:testing container with dpkg-dev.
# Last update 2026/10/15
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${SRC:-${SPARKY_SOURCES:?}/sparky-backup-core-stereo}/9
OUT=${OUT:-${SPARKY_REPO_DIR:?}}
PKG=sparky-backup-core-stereo
SOURCE_VERSION=$(sed -n '2s/^  Version \(.*\) (.*$/\1/p' "$SRC/CHANGELOG")
[ -n "$SOURCE_VERSION" ] || { echo "no version in $SRC/CHANGELOG" >&2; exit 1; }
VERSION=${VERSION:-20261117~sparky9~0+lc1}
# The source is one commit of the fork, never "whatever is checked out": 20261111 was built from a work tree left on
# an older branch (partner/lean-code-20261020), and lost the packer's menu generator, its keyboard layouts and its
# menu languages while every gate passed; the developer ISO of 2026-11-17 could not be packed with it.
# SOURCE_COMMIT names the commit of danielcamposramos/sparky-backup-core (branch stereo) and SOURCE_TREE is the
# fingerprint of its folder 9: sha256 over "path NUL sha256-of-file LF" for every file in path order, __pycache__
# left out. A folder that is not that commit stops the build. To move to a new commit, change both together.
SOURCE_COMMIT=${SOURCE_COMMIT:-8c234115415685d4747651ac457e334099afbeb5}
SOURCE_TREE=${SOURCE_TREE:-5a5471515bb6f26776b46d4a221f711ad450a1811bce04f8e71a8fc61930b10a}
got=$(python3 - "$SRC" <<'FINGERPRINT'
import hashlib, os, sys
root = sys.argv[1]
h = hashlib.sha256()
for folder, folders, files in sorted(os.walk(root)):
    if '__pycache__' in os.path.relpath(folder, root).split(os.sep):
        continue
    for name in sorted(files):
        path = os.path.join(folder, name)
        digest = 'link:' + os.readlink(path) if os.path.islink(path) else hashlib.sha256(open(path, 'rb').read()).hexdigest()
        h.update(os.path.relpath(path, root).encode() + b'\0' + digest.encode() + b'\n')
print(h.hexdigest())
FINGERPRINT
)
[ "$got" = "$SOURCE_TREE" ] || {
	echo "$SRC is not folder 9 of commit $SOURCE_COMMIT (fingerprint $got, expected $SOURCE_TREE)." >&2
	echo "Export that commit (git archive $SOURCE_COMMIT 9) and build from the export; a work tree on another branch gives another packer." >&2
	exit 1
}
for needed in lib/stereo/gen-menus.py lib/stereo/keyboard-layouts lib/stereo/isolinux-head.cfg lib/stereo/lang/en; do
	[ -e "$SRC/$needed" ] || { echo "$SRC has no $needed: the Stereo profile cannot write its menus without it" >&2; exit 1; }
done
grep -q -- '-isohybrid-apm-hfsplus' "$SRC/bin/sparkybackup" || { echo "$SRC/bin/sparkybackup does not write the Apple partition map" >&2; exit 1; }
W=$(mktemp -d "${TMPDIR:-/tmp}/backup-stereo-build.XXXXXX")
trap 'rm -rf "$W"' EXIT
COPY="$HERE/../../../tools/copy-recipe.py"
python3 "$COPY" "$SRC" "$W/input"
SRC=$W/input
patch --batch --forward -d "$SRC" -p1 < "$HERE/core-fonts.patch"
D=$W/$PKG
mkdir -p "$D/DEBIAN" "$D/usr/bin" "$D/etc/sparkybackup" "$D/etc/xdg/autostart" "$D/lib/live/config" \
	"$D/usr/lib/sparkybackup" "$D/usr/share/applications" "$D/usr/share/sparkybackup/idesk" \
	"$D/usr/share/sparky/sparky-advanced-installer" "$D/usr/share/sparky/sparky-backup-core" "$D/usr/share/doc/$PKG"

for f in "$SRC"/bin/*; do [ -f "$f" ] && install -m 755 "$f" "$D/usr/bin/"; done
install -m 644 "$SRC"/etc/* "$D/etc/sparkybackup/"
cp -a "$SRC"/lib/. "$D/usr/lib/sparkybackup/"
# The packer stages current Debian programs when it creates an ISO. Historical
# bundled programs are neither our source builds nor independent update roots.
# Keep the menus and graphics, and use the same explicit list as the packer.
python3 - "$SRC/lib/stage-boot-files.py" "$D/usr/lib/sparkybackup" <<'BOOT_INPUTS'
from pathlib import Path
import runpy, shutil, sys
files = runpy.run_path(sys.argv[1])["FILES"]
tree = Path(sys.argv[2])
for relative in files:
    (tree / relative).unlink(missing_ok=True)
shutil.rmtree(tree / "boot/grub/i386-efi")
for cache in tree.rglob('__pycache__'):
    if cache.is_dir() and not cache.is_symlink():
        shutil.rmtree(cache)
BOOT_INPUTS
install -m 644 "$SRC"/share/*.desktop "$D/usr/share/applications/"
install -m 755 "$SRC"/live/* "$D/lib/live/config/"
install -m 644 "$SRC"/idesk/* "$D/usr/share/sparkybackup/idesk/"
install -m 644 "$SRC"/lang-inst/* "$D/usr/share/sparky/sparky-advanced-installer/"
install -m 644 "$SRC"/lang-core/* "$D/usr/share/sparky/sparky-backup-core/"
install -m 644 "$SRC"/xdg/* "$D/etc/xdg/autostart/"
install -m 644 "$SRC/copyright" "$D/usr/share/doc/$PKG/copyright"
find "$D/usr/lib/sparkybackup" -type d -exec chmod 755 {} + && find "$D/usr/lib/sparkybackup" -type f -exec chmod 644 {} +
(cd "$D" && find etc -type f | sed 's|^|/|' | sort) >"$D/DEBIAN/conffiles"

SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
ORIGINAL_MAINTAINER=$(sed -n '2s/^[[:space:]]*//p' "$SRC/copyright")
cat >"$D/DEBIAN/control" <<EOS
Package: $PKG
Version: $VERSION
Architecture: amd64
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Original-Maintainer: $ORIGINAL_MAINTAINER
Installed-Size: $SIZE
Depends: calamares-settings-sparky-stereo (>= 20261111.1~sparky9~0), apt, bash, btrfs-progs, console-data, coreutils, dialog, dosfstools, dpkg, findutils, gawk, grep, grub-efi-amd64-signed, grub-efi-ia32-unsigned, hwdata, iputils-ping, isolinux, keyboard-configuration, laptop-detect, live-boot, live-config, live-config-systemd, live-boot-initramfs-tools, locales, memtest86+ (>= 8.10), mount, mtools, nano, os-prober, parted, passwd, python3, rsync, sed, shim-signed, sparky-backup-desktop (>= 20180729) | sparky-server, sparky-info, squashfs-tools, syslinux-common, syslinux-utils, systemd, systemd-sysv, util-linux, x11-utils, xfsprogs, xorriso | genisoimage, xz-utils
Recommends: lvm2, cryptsetup, cryptsetup-initramfs, systemd-cryptsetup
Conflicts: sparky-backup-core, sparky-remastersys, sparky-backup-sys (<= 20180606)
Replaces: sparky-backup-core, sparky-backup-sys (<= 20180606)
Provides: sparky-backup-core (= $VERSION)
Suggests: grub-pc, aptitude, cryptsetup-initramfs
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: Sparky Backup Core Stereo
  Sparky Stereo OS's fork of Sparky Backup Core: the same tool to make a
  hybrid ISO image from an installed system, with the boot files taken from
  Debian at every build, and sparkybackup-stereo, the Sparky Stereo OS
  profile (its boot menus, Secure Boot certificate and Lean Code stage).
EOS
(cd "$D" && find . -path ./DEBIAN -prune -o -type f -print | sed 's|^\./||' | sort | tr '\n' '\0' | xargs -0 md5sum >DEBIAN/md5sums)
mkdir -p "$OUT"
mkdir -p "$W/authoring"
python3 "$COPY" "$HERE" "$W/authoring/builder"
cp -a "$SRC" "$W/authoring/upstream"
mkdir -p "$W/authoring/build-tools"
cp "$COPY" "$W/authoring/build-tools/"
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone \
    "$D" "$OUT" --authoring "$W/authoring" --architecture amd64
