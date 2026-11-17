#!/bin/bash
# Phase 2 of mesa-apt.sh, inside a container whose /proc/cpuinfo is a faked processor (apt reads it; the loader and the guard read the fixture).
set -uo pipefail
sh /run/https-only-apt.sh >/dev/null
cp /apt/62sparky-stereo-variants /etc/apt/apt.conf.d/; install -Dm644 /apt/variants/varianttable /usr/share/sparky-stereo-apt/varianttable
[ "$MODE" = install-optout ] && printf 'APT::Architecture-Variants "";\n' >/etc/apt/apt.conf.d/99local
rm -f /etc/apt/sources.list.d/debian.sources
cat >/etc/apt/sources.list.d/debian.sources <<'S'
Types: deb
URIs: https://deb.debian.org/debian
Suites: forky
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.pgp
S
dpkg --add-architecture i386
printf 'deb [trusted=yes] file:/repo mashtabba main\ndeb [trusted=yes] file:/work/mesa/tree mashtabba main\n' >/etc/apt/sources.list.d/sparky.list
apt-get -y update >/dev/null 2>&1 || true
dpkg-deb -x /repo/pool/main/d/deb-multimedia-keyring/deb-multimedia-keyring_*_all.deb /tmp/dmo
printf 'Types: deb\nURIs: https://www.deb-multimedia.org\nSuites: forky\nComponents: main non-free\nSigned-By: /tmp/dmo/usr/share/keyrings/deb-multimedia-keyring.pgp\n' >/etc/apt/sources.list.d/dmo.sources
printf 'Package: *\nPin: release o=Toy variants\nPin-Priority: 1001\n' >/etc/apt/preferences.d/toy
apt-get -y update >/dev/null 2>&1
which_build() {
	local h; h=$(sha256sum /usr/lib/x86_64-linux-gnu/libgallium-*.so | head -1 | cut -d' ' -f1)
	if [ "$h" = "$(sed -n 's/^v3 //p' /work/mesa/hashes)" ]; then echo v3; elif [ "$h" = "$(sed -n 's/^base //p' /work/mesa/hashes)" ]; then echo base; else echo "unknown $h"; fi
}
case "$MODE" in
install|install-optout)
	apt-get -y install libgl1-mesa-dri >/tmp/install.out 2>&1 || { tail -5 /tmp/install.out; echo "install failed"; exit 1; }
	echo "apt chose: $(apt-cache policy mesa-libgallium | sed -n 's/^  Installed: //p') ($(dpkg-query -W -f '${Architecture} ${Architecture-Variant}' mesa-libgallium))"
	# the 32-bit baseline build beside the 64-bit build chosen for this processor (Multi-Arch: same twins of different architectures)
	if apt-get -y install libgl1-mesa-dri:i386 >/tmp/i386.out 2>&1; then echo "the i386 build installs beside it: $(dpkg-query -W -f '${Package}:${Architecture} ${Version}' libgl1-mesa-dri:i386)"; else tail -4 /tmp/i386.out; echo "i386 co-installation failed"; exit 1; fi
	echo "result: $(which_build)";;
guard)
	apt-get -y install /work/mesa/v3/libgl1-mesa-dri_*_amd64v3.deb /work/mesa/v3/mesa-libgallium_*_amd64v3.deb >/tmp/install.out 2>&1 || { tail -5 /tmp/install.out; echo "install failed"; exit 1; }
	apt-get -y install sparky-stereo-problems >/dev/null 2>&1 || { echo "sparky-stereo-problems not installed"; exit 1; }
	dpkg-deb -x /hw/sparky-stereo-hardware_*_all.deb /
	mkdir -p /tmp/fix
	printf '    x86-64-v2 (supported, searched)\n    x86-64-v1 (baseline)\n' >/tmp/fix/ldso-help
	dpkg-query -W -f '${db:Status-Abbrev}\t${Package}\t${Architecture-Variant}\n' >/tmp/fix/installed
	echo "installed with a variant field: $(awk -F'\t' '$3 != ""' /tmp/fix/installed | wc -l)"
	SPARKY_VARIANT_FIXTURE=/tmp/fix /usr/lib/sparky-stereo-hardware/variant-check check
	sparky-stereo-problems list 2>&1 | cut -c1-600
	if sparky-stereo-problems list 2>&1 | grep -q "built for a higher x86-64 level"; then echo "result: guard"; else echo "result: no notice"; fi;;
esac
