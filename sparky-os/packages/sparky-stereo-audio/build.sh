#!/bin/bash
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/16
# Copyright 2026 under the GNU GPL3 License
# Builds sparky-stereo-audio: the sound defaults of Daniel's design (ORDER item 20, built as ORDER 631). The sound system
# follows the rate of what plays; the allowed rates come from the computer's own sound devices (sparky-stereo-audio detect,
# at install, at boot and when a card comes or goes), the conversion quality from a measurement of the processor, and a
# device that takes only 16 bit gets dither. Drop-ins named 00-sparky-stereo-audio.conf, so every file of the person wins.
# What fails is said and kept by sparky-stereo-problems (ORDER 350); the messages are built into journal catalogs.
# Needs dpkg-deb and sparky-stereo-problems; run it in a throwaway container or on any Debian.
# Last update 2026/11/16
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-${SPARKY_REPO_DIR:?}}
VERSION=0.3.0+lc1
PKG=sparky-stereo-audio
W=$(mktemp -d "${TMPDIR:-${SPARKY_SCRATCH:?}}/audio-build.XXXXXX")
trap 'rm -rf "$W"' EXIT
D=$W/$PKG
mkdir -p "$D/DEBIAN" "$D/usr/bin" "$D/usr/share/sparky/$PKG" "$D/usr/share/doc/$PKG" \
	"$D/usr/lib/systemd/system/multi-user.target.wants" "$D/usr/lib/systemd/user/default.target.wants" \
	"$D/usr/lib/sparky-stereo-audio" "$D/usr/share/wireplumber/scripts" "$D/usr/share/wireplumber/wireplumber.conf.d" \
	"$D/usr/lib/udev/rules.d" "$D/usr/lib/systemd/catalog"

install -m 755 "$HERE/bin/sparky-stereo-audio" "$D/usr/bin/"
mkdir -p "$D/usr/share/applications" "$D/etc/xdg" "$D/usr/lib/modules-load.d"
printf '[Desktop Entry]\nType=Application\nName=FluidSynth\nExec=sparky-stereo-audio midi --play %%f\nIcon=audio-x-generic\nTerminal=false\nCategories=AudioVideo;Audio;\nMimeType=audio/midi;audio/x-midi;\n' > "$D/usr/share/applications/sparky-stereo-midi.desktop"
printf '[Default Applications]\naudio/midi=sparky-stereo-midi.desktop\naudio/x-midi=sparky-stereo-midi.desktop\n' > "$D/etc/xdg/mimeapps.list"
printf '/etc/xdg/mimeapps.list\n' > "$D/DEBIAN/conffiles"
printf '# General MIDI ports for ALSA programs, including software-only games.\nsnd_seq\n' > "$D/usr/lib/modules-load.d/sparky-stereo-midi.conf"
mkdir -p "$D/usr/lib/systemd/user/fluidsynth.service.d"
install -m 644 "$HERE/systemd/fluidsynth-override.conf" "$D/usr/lib/systemd/user/fluidsynth.service.d/00-sparky-midi.conf"
ln -s ../fluidsynth.service "$D/usr/lib/systemd/user/default.target.wants/fluidsynth.service"
install -m 644 "$HERE"/lib/*.py "$D/usr/lib/sparky-stereo-audio/"
install -m 644 "$HERE/wireplumber/sparky-stereo-audio.lua" "$D/usr/share/wireplumber/scripts/"
install -m 644 "$HERE/wireplumber/00-sparky-stereo-surround.conf" "$D/usr/share/wireplumber/wireplumber.conf.d/"
install -m 644 "$HERE/systemd/sparky-stereo-audio-monitor.service" "$D/usr/lib/systemd/user/"
ln -s ../sparky-stereo-audio-monitor.service "$D/usr/lib/systemd/user/default.target.wants/sparky-stereo-audio-monitor.service"
install -m 644 "$HERE"/lang/* "$D/usr/share/sparky/$PKG/"
install -m 644 "$HERE/README.md" "$D/usr/share/doc/$PKG/README.md"
install -m 644 "$HERE/CHANGELOG" "$D/usr/share/doc/$PKG/CHANGELOG"
install -m 644 "$HERE/copyright" "$D/usr/share/doc/$PKG/copyright"
install -m 644 "$HERE/systemd/sparky-stereo-audio.service" "$D/usr/lib/systemd/system/"
install -m 644 "$HERE/systemd/sparky-stereo-audio-apply.service" "$HERE/systemd/sparky-stereo-audio-apply.path" "$D/usr/lib/systemd/user/"
install -m 644 "$HERE/udev/71-sparky-stereo-audio.rules" "$D/usr/lib/udev/rules.d/"
ln -s ../sparky-stereo-audio.service "$D/usr/lib/systemd/system/multi-user.target.wants/sparky-stereo-audio.service"
ln -s ../sparky-stereo-audio-apply.path "$D/usr/lib/systemd/user/default.target.wants/sparky-stereo-audio-apply.path"
ln -s ../sparky-stereo-audio-apply.service "$D/usr/lib/systemd/user/default.target.wants/sparky-stereo-audio-apply.service"
# the package's failure messages (LOCAL20 to LOCAL23), word for word, as journal catalogs the engine reads in the person's language
sparky-stereo-problems catalog $PKG "$HERE/lang" "$D/usr/lib/systemd/catalog" --subject LOCAL1 --keys LOCAL20,LOCAL21,LOCAL22,LOCAL23,LOCAL27,LOCAL29,LOCAL40,LOCAL41,LOCAL53,LOCAL54,LOCAL55

# The program says and keeps what fails (sparky-stereo-problems); the package configures either way, as debhelper's own
# service starts do, and `sparky-stereo-audio detect --write` does the step again.
cat >"$D/DEBIAN/postinst" <<'EOS'
#!/bin/sh
# postinst script
set -e
if [ "$1" = "configure" ]; then
	/usr/bin/sparky-stereo-audio detect --write >/dev/null || :
	if [ -d /run/systemd/system ]; then
		udevadm control --reload 2>/dev/null || :
	fi
fi
exit 0
EOS
cat >"$D/DEBIAN/postrm" <<'EOS'
#!/bin/sh
# postrm script
set -e
if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
	# only the files this package wrote carry its mark; a file of the person with the same name stays
	for f in /etc/pipewire/pipewire.conf.d /etc/pipewire/client.conf.d /etc/pipewire/pipewire-pulse.conf.d /etc/wireplumber/wireplumber.conf.d; do
		p=$f/00-sparky-stereo-audio.conf
		if [ -f "$p" ] && head -n 1 "$p" | grep -q '^# sparky-stereo-audio:'; then
			rm -f "$p" || echo "sparky-stereo-audio: $p could not be removed: it keeps the sound defaults of the removed package. Remove it by hand." >&2
		fi
	done
	if command -v sparky-stereo-problems >/dev/null; then
		sparky-stereo-problems clear --all sparky-stereo-audio || :
	fi
fi
if [ "$1" = "purge" ]; then
	rm -rf /var/lib/sparky-stereo-audio
fi
exit 0
EOS
chmod 755 "$D/DEBIAN/postinst" "$D/DEBIAN/postrm"

SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOS
Package: $PKG
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: sparky-stereo-midi (>= 0.1.0), fluidsynth (>= 2.6.1), timgm6mb-soundfont, pipewire-jack, alsa-utils, pipewire (>= 1.6.9), pipewire-bin, pipewire-pulse, pulseaudio-utils, libmysofa-utils, python3, sparky-stereo-problems (>= 0.2.0), systemd, wireplumber (>= 0.5.19)
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: Sparky Stereo high fidelity sound defaults
  The sound system follows the rate of what plays, so a file is converted only
  when the sound device cannot take its rate, and then at the highest quality
  the processor carries. The rates come from the computer's own sound devices
  (HDA codecs, displays' audio blocks, USB DACs), 44100 and 48000 Hz always.
  A device that takes only 16 bit gets triangular dither.
  Drop-ins named 00-sparky-stereo-audio.conf: every file of the person wins.
  What cannot be read or written is said and kept by sparky-stereo-problems.
EOS
(cd "$D" && find . -path ./DEBIAN -prune -o -type f -print | sed 's|^\./||' | sort | tr '\n' '\0' | xargs -0 md5sum >DEBIAN/md5sums)
mkdir -p "$OUT"
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone "$D" "$OUT" --authoring "$HERE"
echo "built $OUT/${PKG}_${VERSION}_all.deb"
