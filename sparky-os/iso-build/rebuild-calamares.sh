#!/bin/sh
# Rebuilds the edition's calamares from its published source package with SparkyLinux's four helper
# modules executable again (bootloader-eficonfig, secure-boot-fix, secure-boot-install, sparkyhooks).
# Calamares runs them directly, and CMake installs every file of a module folder with mode 644
# (install FILES), so the installer stopped at grubefiinstall: "Permission denied", exit code 126.
# SparkyLinux's own calamares 3.4.3~sparky9~4-1 ships the four with mode 755; this gives the same.
# Runs in beta-iso-lutz-build:1 (Debian testing), 4 CPUs, the tree on the build disk.
# Usage: rebuild-calamares.sh SOURCE.dsc OUTDIR [WORKDIR]
set -eu
DSC=$(readlink -f "$1"); OUT=$(readlink -f "$2"); WORK=${3:-/mnt/build/beta-iso-lutz/calamares-build}
OLD=$(sed -n 's/^Version: //p' "$DSC")
NEW=${OLD%+stereo3d*}+stereo3d$(( ${OLD##*+stereo3d} + 1 ))
mkdir -p "$OUT" "$WORK"
cp "$DSC" "$(dirname "$DSC")"/calamares_"${OLD%-*}".orig.tar.xz "$(dirname "$DSC")"/calamares_"$OLD".debian.tar.xz "$WORK/"
docker run --rm --name beta-iso-lutz-calamares --cpus 4 --memory 12g -v "$WORK:/w" -v "$OUT:/out" \
	-e OLD="$OLD" -e NEW="$NEW" -e HOSTUID="$(id -u):$(id -g)" beta-iso-lutz-build:1 sh -ec '
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends dpkg-dev devscripts equivs >/dev/null
cd /w
rm -rf calamares-src
dpkg-source -x calamares_$OLD.dsc calamares-src
cd calamares-src
# the four helper modules, by name: SparkyLinux ships exactly these with mode 755
cat >>debian/rules <<"EOR"

# SparkyLinux'"'"'s helper modules are programs Calamares runs directly; CMake installs every file of a
# module folder with mode 644 (install FILES), SparkyLinux ships these four with mode 755.
SPARKY_HELPERS = grubefiinstall/bootloader-eficonfig securebootfix/secure-boot-fix \
	securebootinstall/secure-boot-install sparkyhooks/sparkyhooks
execute_after_dh_fixperms:
	for f in $(SPARKY_HELPERS); do \
		chmod 755 debian/calamares/usr/lib/$(DEB_HOST_MULTIARCH)/calamares/modules/$$f; \
	done
EOR
grep -q "^include /usr/share/dpkg/architecture.mk" debian/rules || \
	sed -i "0,/^%:/s//include \/usr\/share\/dpkg\/architecture.mk\n\n%:/" debian/rules
# a changelog entry of its own (dch would fold it into the UNRELEASED entry above)
{
	echo "calamares ($NEW) UNRELEASED; urgency=medium"
	echo
	echo "  * Install SparkyLinux'"'"'s four helper modules (bootloader-eficonfig,"
	echo "    secure-boot-fix, secure-boot-install, sparkyhooks) with mode 755, as"
	echo "    SparkyLinux ships them: Calamares runs them directly, and the"
	echo "    installer stopped at grubefiinstall with Permission denied (exit"
	echo "    code 126)."
	echo
	echo " -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  $(date -R)"
	echo
	cat debian/changelog
} > debian/changelog.new
mv debian/changelog.new debian/changelog
mk-build-deps -i -r -t "apt-get -y -qq --no-install-recommends" debian/control >/dev/null
dpkg-buildpackage -us -uc -j4 -sa >/w/build.log 2>&1 || { tail -40 /w/build.log; exit 1; }
cd /w
cp calamares_${NEW}_amd64.deb calamares_${NEW}.dsc calamares_${NEW}.debian.tar.xz /out/
ls calamares-dbgsym_${NEW}_amd64.deb >/dev/null 2>&1 && cp calamares-dbgsym_${NEW}_amd64.deb /out/ || true
chown -R "$HOSTUID" /w /out
'
echo "built $OUT/calamares_${NEW}_amd64.deb"
dpkg-deb -c "$OUT/calamares_${NEW}_amd64.deb" | grep -E 'grubefiinstall/bootloader-eficonfig|securebootfix/secure-boot-fix|securebootinstall/secure-boot-install|sparkyhooks/sparkyhooks$'
