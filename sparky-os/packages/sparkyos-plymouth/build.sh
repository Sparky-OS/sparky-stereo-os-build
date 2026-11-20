#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/16
# Copyright 2026 under the GNU GPL3 License
# Builds sparkyos-plymouth, the SparkyOS boot splash, from the artwork repository's plymouth/ folder
# at the commit pinned below (ART_COMMIT, with the plymouth/ tree's hash: a work tree's current
# checkout is never a source, ORDER 715; 9~20261102+lc1 was built from a checkout left on an older branch
# and shipped the old squeezed pair): the themes sparkyos-stereo (every screen: both eyes on a stereo output, which the edition's
# Plymouth gives a theme declaring Stereo=full-side-by-side, one picture elsewhere) and sparkyos (2D),
# installed where its install.sh puts them. sparkyos-stereo becomes the default theme, as sparky-plymouth
# makes sparky-blue SparkyLinux's. sparky-plymouth sets sparky-blue again at every upgrade, whatever theme
# was chosen; a trigger on its theme then sets this package's default back, when this package had set it.
# Removing this package gives sparky-blue back.
# Last update 2026/11/18
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ART_REPO=${ART_REPO:-${SPARKY_SCRATCH:?}/sparky-os/artwork-repo}
# the artwork source: this commit of the artwork repository (branch main) and the hash of its plymouth/ tree
ART_COMMIT=971cf82ce288b9561153592b8c92064edb808197
ART_TREE=ce3d2dd21b3fbe16a89419c533685e336a5d6d85
OUT=${OUT:-${SPARKY_REPO_DIR:?}}
PKG=sparkyos-plymouth
VERSION=$(sed -n '2s/^  Version \([^ ]*\) .*/\1/p' "$HERE/CHANGELOG")
VERSION=$VERSION+lc1
. "$HERE/../../repo/build-provenance.sh"
sparky_provenance_init "${SPARKY_BUILD_IMAGE:?name the build image (python3, dpkg-dev, fakeroot, debhelper, git, gcc, nodejs, node-acorn, perl)}" "$HERE"
umask 022
W=$(mktemp -d "${TMPDIR:-/tmp}/sparkyos-plymouth.XXXXXX")
trap 'rm -rf "$W"' EXIT
COPY="$HERE/../../../tools/copy-recipe.py"
# the pinned commit must exist and its plymouth/ tree must be the pinned one; nothing else is read from the repository
[ "$(git -C "$ART_REPO" rev-parse --verify "$ART_COMMIT^{commit}")" = "$ART_COMMIT" ] ||
	{ echo "build.sh: $ART_REPO has no commit $ART_COMMIT" >&2; exit 1; }
[ "$(git -C "$ART_REPO" rev-parse --verify "$ART_COMMIT:plymouth")" = "$ART_TREE" ] ||
	{ echo "build.sh: the plymouth/ tree of $ART_COMMIT is not $ART_TREE" >&2; exit 1; }
mkdir -p "$W/export"
git -C "$ART_REPO" archive "$ART_COMMIT" plymouth | tar -x -C "$W/export"
python3 "$COPY" "$W/export/plymouth" "$W/input"
ART=$W/input
D=$W/$PKG
mkdir -p "$D/DEBIAN" "$D/usr/share/plymouth/themes" "$D/usr/share/doc/$PKG"
for t in sparkyos sparkyos-stereo; do
	cp -r "$ART/$t" "$D/usr/share/plymouth/themes/"
done
cp "$ART/copyright" "$D/usr/share/doc/$PKG/copyright"
cp "$ART/README.md" "$D/usr/share/doc/$PKG/README.md"
cat >"$D/DEBIAN/postinst" <<'EOS'
#!/bin/sh
# postinst script
set -e
STATE=/var/lib/sparkyos-plymouth/theme
DEFAULT=sparkyos-stereo
current() { plymouth-set-default-theme 2>/dev/null || true; }
case "$1" in
	configure)
		# a first install makes sparkyos-stereo the default; an upgrade keeps the owner's choice, and moves
		# the default this package set before 9~20261016.1 (sparkyos) to sparkyos-stereo
		cur=$(current)
		if [ -z "$2" ] || [ "$cur" = sparky-blue ] || { dpkg --compare-versions "$2" lt 9~20261016.1 && [ "$cur" = sparkyos ] && [ "$(cat "$STATE" 2>/dev/null)" = sparkyos ]; }; then
			plymouth-set-default-theme "$DEFAULT"
			mkdir -p /var/lib/sparkyos-plymouth
			echo "$DEFAULT" >"$STATE"
		elif [ "$cur" != "$(cat "$STATE" 2>/dev/null || true)" ]; then
			# the owner chose another theme: the trigger below leaves it alone from now on
			rm -f "$STATE"
		fi
	;;
	triggered)
		# sparky-plymouth's upgrade sets sparky-blue: this package's default again, if it had set it
		s=$(cat "$STATE" 2>/dev/null || true)
		if [ "$(current)" = sparky-blue ] && [ -n "$s" ] && [ -e "/usr/share/plymouth/themes/$s/$s.plymouth" ]; then
			plymouth-set-default-theme "$s"
		fi
	;;
esac
exit 0
EOS
cat >"$D/DEBIAN/postrm" <<'EOS'
#!/bin/sh
# postrm script
set -e
if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
	# the configured theme, read from the file: the theme's own files are gone by now
	s=$(cat /var/lib/sparkyos-plymouth/theme 2>/dev/null || true)
	t=$(sed -n 's/^[[:space:]]*Theme[[:space:]]*=[[:space:]]*//p' /etc/plymouth/plymouthd.conf 2>/dev/null | tail -n1)
	if [ -n "$s" ] && [ "$t" = "$s" ] && [ -e /usr/share/plymouth/themes/sparky-blue/sparky-blue.plymouth ]; then
		plymouth-set-default-theme sparky-blue || true
	fi
	rm -rf /var/lib/sparkyos-plymouth
fi
exit 0
EOS
printf 'interest-noawait /usr/share/plymouth/themes/sparky-blue\nactivate-noawait update-initramfs\n' >"$D/DEBIAN/triggers"
chmod 755 "$D/DEBIAN/postinst" "$D/DEBIAN/postrm"
find "$D" -path "$D/DEBIAN" -prune -o -type d -exec chmod 755 {} + ; find "$D" -path "$D/DEBIAN" -prune -o -type f -exec chmod 644 {} +
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOS
Package: $PKG
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: plymouth (>= 26.134.222-1+stereo3d4), plymouth-themes
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: SparkyOS Plymouth Themes
  The SparkyOS boot splash: the Debian swirl with its orbits and electrons
  on the Sparky background, and the SPARKYOS / POWERED BY DEBIAN / STEREO 3D
  EDITION wordmark. Two themes: sparkyos-stereo, the default, which draws
  both eyes at full size inside the person's depth limits on a stereo
  output and one picture elsewhere, and sparkyos, in 2D.
EOS
(cd "$D" && find . -path ./DEBIAN -prune -o -type f -print | sed 's|^\./||' | sort | tr '\n' '\0' | xargs -0 md5sum >DEBIAN/md5sums)
mkdir -p "$OUT"
mkdir -p "$W/authoring"
python3 "$COPY" "$HERE" "$W/authoring"
cp -a "$ART" "$W/authoring/artwork"
mkdir -p "$W/authoring/build-tools"
cp "$COPY" "$W/authoring/build-tools/"
printf 'artwork repository commit %s\nplymouth/ tree %s\n' "$ART_COMMIT" "$ART_TREE" > "$W/authoring/artwork/SOURCE"
# the standalone package is sealed in the build image, its source package is built again with dpkg-buildpackage
# (repo/rebuild-script-source.py) and check-debs writes the complete build record (ORDER 639, ORDER 715)
TREE=$(cd "$HERE/../../.." && pwd)
IMAGE=$SPARKY_BUILD_IMAGE
chmod -R a+rX "$W"
docker run --rm --pull=never --name "${SPARKY_CONTAINER_PREFIX:+$SPARKY_CONTAINER_PREFIX-}lean-standalone-sparkyos-plymouth" --ulimit core=1 --network none --platform linux/amd64 \
	--user "$(id -u):$(id -g)" "${SPARKY_PROV_ARGS[@]}" -e HOME=/tmp -e PYTHONPATH="$TREE/sparky-os" \
	-e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' \
	--mount "type=bind,src=$TREE,dst=$TREE,readonly" --mount "type=bind,src=$W,dst=$W" --mount "type=bind,src=$OUT,dst=$OUT" "$IMAGE" \
	sh -c 'python3 -m lean.standalone "$1/$4" "$2" --authoring "$1/authoring" && python3 "$PYTHONPATH/repo/rebuild-script-source.py" "$2/$4_$5.dsc" && cd "$2" && python3 -m lean.release check-debs ./*_all.deb' \
	sh "$W" "$OUT" "$HERE" "$PKG" "$VERSION"
