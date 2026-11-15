#!/bin/bash
# Sparky Stereo OS looks (Daniel, 2026-10-02), as three packages:
#   sparky-stereo-look             the default: Oxygen in dark mode, whole (colours, Plasma
#                                  style, icons, cursor, application style and window
#                                  decoration), Daniel's transparency, glide and wobbly windows
#   sparky-stereo-look-sparkyblack Sparky black, fixed (splash set, the real cursor name,
#                                  no QtCurve): global theme, Plasma style, icons and
#                                  cursor, Plymouth sparky-lines, SDDM sparky-stereo-black, the
#                                  GRUB background
#   sparky-stereo-look-qplatinum   the System 8 look: QPlatinum (Platinum) style, colours and window
#                                  decoration (Zinjanthr0pus), with Sparky black's icons,
#                                  cursor and splash
# The art comes from where it is installed on Daniel's system (the edition's build host);
# the theme definitions and fixes are in this folder.
# Usage: build.sh [all|default]   (packages land in $OUT, default ${SPARKY_REPO_DIR})
# Version history in CHANGELOG; fixes offered to Pawel in upstream-patches/.
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(mkdir -p "${OUT:-${SPARKY_REPO_DIR:?}}" && cd "${OUT:-${SPARKY_REPO_DIR:?}}" && pwd)
# the host's facts for the build record, and the source date from the recipe's last commit (ORDER 394b, ORDER 421b)
. "$HERE/../../repo/build-provenance.sh"
IMAGE=${SPARKY_BUILD_IMAGE:-sparky-lc-migration:20261020}
sparky_provenance_init "$IMAGE" "$HERE"
TREE=$(cd "$HERE/../../.." && pwd)
VERSION=${VERSION:-20261115~sparky9~0+lc1}   # generation-tied (skill); sorts above the first 1.0~dev1 builds
case ${1:-all} in all|default) ;; *) echo 'Usage: build.sh [all|default]' >&2; exit 2 ;; esac
WORK=$(mktemp -d "${TMPDIR:-${SPARKY_SCRATCH:?}/sparky-os}/look-build.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
RECIPE=$HERE
COPY="$RECIPE/../../../tools/copy-recipe.py"
python3 "$COPY" "$RECIPE" "$WORK/authoring"
mkdir -p "$WORK/authoring/build-tools"
cp "$COPY" "$WORK/authoring/build-tools/"
HERE=$WORK/authoring
LNF=usr/share/plasma/look-and-feel
OXYGEN=/usr/share/plasma/look-and-feel/org.kde.oxygen
SB=/usr/share/plasma/look-and-feel/org.kde.sparkyblack.desktop
QP=$HOME/.local/share/plasma/desktoptheme/QPlatinum
QPDECO=$HOME/.local/share/aurorae/themes/QPlatinum22p
mkdir -p "$OUT"

control() { # dir package depends recommends description...
	local d=$1 p=$2 dep=$3 rec=$4; shift 4
	mkdir -p "$d/DEBIAN" "$d/usr/share/doc/$p"
	{
		echo "Package: $p"
		echo "Version: $VERSION"
		echo "Architecture: all"
		echo "Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>"
		echo "Section: kde"
		echo "Priority: optional"
		[ -n "$dep" ] && echo "Depends: $dep"
		[ -n "$rec" ] && echo "Recommends: $rec"
		echo "Description: $1"
		shift
		for l in "$@"; do echo " $l"; done
	} >"$d/DEBIAN/control"
}
build() { # dir package: the Lean Code package and its source, then the gate that writes the build record, in the build image
	find "$1" -name '*.qmlc' -delete
	chmod -R go-w "$1"
	docker run --rm --name "${SPARKY_CONTAINER_PREFIX:+$SPARKY_CONTAINER_PREFIX-}lean-standalone-$2" --ulimit core=0 --network none --platform linux/amd64 \
		--user "$(id -u):$(id -g)" "${SPARKY_PROV_ARGS[@]}" -e HOME=/tmp -e PYTHONPATH="$TREE/sparky-os" \
		-e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' \
		-v "$TREE":"$TREE":ro -v "$1":"$1" -v "$OUT":"$OUT" "$IMAGE" \
		sh -c 'python3 -m lean.standalone "$1" "$2" --authoring "$3" && cd "$2" && python3 -m lean.release check-debs "./$4_$5_all.deb" "./$4-lc-hr_$5_all.deb"' \
		sh "$1" "$OUT" "$RECIPE" "$2" "$VERSION"
}

# 1. The default look.
D=$WORK/sparky-stereo-look
T=$D/$LNF/org.sparkystereo.desktop
mkdir -p "$T/contents" "$D/etc/xdg" "$D/usr/share/kglobalaccel" "$D/usr/share/plasma/desktoptheme" "$D/usr/share/color-schemes"
cp "$HERE/default/color-schemes/SparkyStereoOxygenDark.colors" "$D/usr/share/color-schemes/"   # Oxygen Dark with a readable active title
# Sparky Stereo Oxygen: Oxygen's Plasma style with every background at 91 % alpha, foreground inherited from Oxygen
cp -a "$HERE/default/desktoptheme/sparky-stereo-oxygen" "$D/usr/share/plasma/desktoptheme/"
cp "$HERE/default/kglobalaccel/org.sparkystereo.systemmonitor.desktop" "$D/usr/share/kglobalaccel/"
cp "$HERE/default/org.sparkystereo.desktop/metadata.json" "$T/"
cp "$HERE/default/org.sparkystereo.desktop/contents/defaults" "$T/contents/"
cp -a "$HERE/default/org.sparkystereo.desktop/contents/layouts" "$T/contents/"
# the global theme's previews are Oxygen's; the splash's preview is ours, a capture of our loading screen
cp -a "$OXYGEN/contents/previews" "$T/contents/"
cp "$HERE/default/previews/splash.png" "$T/contents/previews/splash.png"
# the loading screen is ours (ORDER 571): the boot splash's picture, its pictures the same files as sparky-stereo-plymouth's
# (tests/splash-pictures.sh), each part at the boot splash's level inside the person's limits through org.sparky.stereo
cp -a "$HERE/default/splash" "$T/contents/"
cp "$HERE/default/xdg/kdeglobals" "$HERE/default/xdg/kwinrc" "$HERE/default/xdg/kde-mimeapps.list" "$HERE/default/xdg/krunnerrc" "$HERE/default/xdg/konsolerc" "$HERE/default/xdg/dolphinrc" "$HERE/default/xdg/ksplashrc" "$D/etc/xdg/"
install -D -m 755 "$HERE/default/first-login-input-method" "$D/usr/lib/sparky-stereo-look/first-login-input-method"
install -D -m 644 "$HERE/default/xdg/plasma-workspace/env/10-sparky-stereo-input-method.sh" \
	"$D/etc/xdg/plasma-workspace/env/10-sparky-stereo-input-method.sh"
install -D -m 644 "$HERE/default/needrestart.conf" "$D/etc/needrestart/conf.d/90-sparky-stereo.conf"
install -D -m 644 "$HERE/default/flathub.flatpakrepo" "$D/usr/share/flatpak/remotes.d/flathub.flatpakrepo"
control "$D" sparky-stereo-look \
	"plasma-workspace (>= 4:6.7.4-2+stereo3d6), plasma-theme-oxygen, oxygen-icon-theme, oxygencursors, kde-style-oxygen-qt6, kwin-decoration-oxygen, kwin-style-aurorae, libkf6config-bin, plasma-runners-addons (>= 4:6.7.4-1+stereo3d1), plasma-systemmonitor, sparky-stereo-gtk, qml6-module-qtquick, libstereo-layer1 (>= 1.20.0)" \
	"kde-style-oxygen-qt5, sparkyos-artwork, sparky-stereo-look-kubabbar-glass" \
	"Sparky Stereo OS default look: Oxygen dark" \
	"The edition's default global theme: Oxygen, whole, in its dark colours:" \
	"Plasma style (Sparky Stereo Oxygen: Oxygen's, with widget, panel, tooltip and" \
	"dialog backgrounds at 91 % alpha, the background only, blur and contrast off)," \
	"Plasma style, icons, cursor and the Oxygen application style, with" \
	"Plastik's square, Windows-like window buttons. Also sets the default KWin effects: translucency" \
	"with Daniel Ramos's values, glide and wobbly windows, and makes VLC Stereo the" \
	"default video player (/etc/xdg/kde-mimeapps.list; a user's own choice still wins)." \
	"In Dolphin's split view the inactive pane's background is translucent. The colours are" \
	"Oxygen Dark with a readable active window title (Sparky Stereo Oxygen Dark)." \
	"Search lists installed applications first, then settings. Power actions and" \
	"unit conversion remain available. Currency rates refresh only when converting a currency." \
	"Web search and the online dictionary are off by default." \
	"Ctrl+Alt+Del, Ctrl+Shift+Esc and Ctrl+Esc open System Monitor; existing shortcuts remain available." \
	"Japanese, Korean and Chinese sessions default to the installed Fcitx5 input" \
	"method before KWin starts, preserving an existing or explicitly disabled choice." \
	"The loading screen after the login is the boot splash's picture, so the" \
	"screen is one picture from power-on to the desktop. On a screen in a 3D" \
	"mode each part stands at the boot splash's depth, inside the person's" \
	"limits for that screen; on a 2D screen it is plain. /etc/xdg/ksplashrc" \
	"names it, and a person who chose another splash keeps it."
printf '%s\n' /etc/xdg/kdeglobals /etc/xdg/kwinrc /etc/xdg/kde-mimeapps.list /etc/xdg/krunnerrc /etc/xdg/konsolerc /etc/xdg/dolphinrc /etc/xdg/ksplashrc \
	/etc/xdg/plasma-workspace/env/10-sparky-stereo-input-method.sh \
	/etc/needrestart/conf.d/90-sparky-stereo.conf >"$D/DEBIAN/conffiles"
cat >"$D/usr/share/doc/sparky-stereo-look/copyright" <<'EOF'
Sparky Stereo OS default look.
Theme definition and defaults: Copyright 2026 Daniel Ramos (Capitain Jack), GPL-2.0-or-later.
Global theme previews (preview.png, fullscreenpreview.jpg): copied from KDE's Oxygen global theme
(plasma-theme-oxygen), Copyright the Oxygen team, under its own licence (see
/usr/share/doc/plasma-theme-oxygen/copyright).
Loading screen (contents/splash/Splash.qml, contents/previews/splash.png): Copyright 2026 Daniel Ramos
(Capitain Jack), GPL-2.0-or-later; KSplash, which shows it, is KDE's (plasma-workspace, Marco Martin and KDE).
Its pictures (contents/splash/images) are those of sparky-stereo-plymouth's boot splash, with the credits
its copyright file gives them: background.png, logo.png and electron.png from Sparky's lines theme,
Copyright 2014 Juliette Taka Belin and Aurelien Couderc (Debian 8 "Jessie" lines theme), Copyright
2018-2020 Pawel "pavroo" Pijanowski and Daniel Ramos (sparky-lines, the Sparky black set), GPL-2+;
wordmark.png, the SparkyOS logo (SPARKYOS / POWERED BY DEBIAN / STEREO 3D EDITION), Copyright 2026
Daniel Ramos (Capitain Jack), GPL-2+.
Sparky Stereo Oxygen Plasma style: derived from KDE's Oxygen Plasma style (plasma-theme-oxygen),
Copyright The Oxygen Project, GPL; only its background SVGs are changed (91 % alpha), its
foreground artwork is inherited; licence texts in /usr/share/plasma/desktoptheme/sparky-stereo-oxygen/.
On Debian systems the GPL is in /usr/share/common-licenses/GPL-2.
EOF
install -m 644 "$HERE/README.md" "$D/usr/share/doc/sparky-stereo-look/README"
build "$D" sparky-stereo-look
[ "${1:-all}" != default ] || exit 0

# 2. Sparky black, fixed.
D=$WORK/sparky-stereo-look-sparkyblack
mkdir -p "$D/$LNF" "$D/usr/share/plasma/desktoptheme" "$D/usr/share/icons" \
	"$D/usr/share/plymouth/themes" "$D/usr/share/sddm/themes" "$D/usr/share/sparky-stereo/grub"
cp -a "$SB" "$D/$LNF/"
rm -f "$D/$LNF/org.kde.sparkyblack.desktop/metadata.desktop"
cp "$HERE/sparkyblack/splash/Splash.qml" "$D/$LNF/org.kde.sparkyblack.desktop/contents/splash/Splash.qml"   # bottomRect fix
cp "$HERE/sparkyblack/metadata.json" "$D/$LNF/org.kde.sparkyblack.desktop/"
cp "$HERE/sparkyblack/defaults" "$D/$LNF/org.kde.sparkyblack.desktop/contents/defaults"
cp -a /usr/share/plasma/desktoptheme/sparkyblack "$D/usr/share/plasma/desktoptheme/"
rsync -a --exclude=.directory /usr/share/icons/sparkyblack "$D/usr/share/icons/"   # .directory: a root-only folder-view file
cp -a /usr/share/plymouth/themes/sparky-lines "$D/usr/share/plymouth/themes/"
# Our own Qt 6 port of Pawel's sparky-black SDDM theme, under our own name (his is never modified)
cp -a "$HERE/sparkyblack/sddm/sparky-stereo-black" "$D/usr/share/sddm/themes/"
cp /opt/artwork/sparky-black.png "$D/usr/share/sparky-stereo/grub/"
control "$D" sparky-stereo-look-sparkyblack "sparky-stereo-look, kwin-style-aurorae, qt6ct" "plymouth, sddm" \
	"Sparky black look, end to end" \
	"Daniel Ramos's Sparky black: the global theme (fixed: it sets its" \
	"splash, names the cursor that exists, and uses the qt6ct style instead of" \
	"QtCurve, which has no Qt 6 build), the Plasma style, icons and cursor, the" \
	"Plymouth theme sparky-lines, the SDDM theme sparky-stereo-black (a Qt 6 port) and the GRUB" \
	"background (in /usr/share/sparky-stereo/grub, not activated)."
cat >"$D/usr/share/doc/sparky-stereo-look-sparkyblack/copyright" <<'EOF'
Sparky black.
Global theme, Plasma style, icons, cursor, GRUB background: Copyright Daniel Ramos (Capitain Jack),
GPL-2.0-or-later (global theme) and GPL-3.0-or-later (Plasma style); based on Oxygen.
Plymouth sparky-lines: a modified Debian 8 "Jessie" lines theme, GPL-2.0-or-later.
SDDM sparky-stereo-black: David Edmundson, Pawel Pijanowski (pavroo), Daniel Ramos (Capitain Jack);
derived from the Breeze SDDM theme; ported to Qt 6 by Daniel Ramos (Capitain Jack) 2026.
Splash: Marco Martin (KDE, Oxygen), with the bottomRect fix by Daniel Ramos (Capitain Jack).
On Debian systems the GPL is in /usr/share/common-licenses/.
EOF
build "$D" sparky-stereo-look-sparkyblack

# 3. QPlatinum, the System 8 look (Mac OS 8's Platinum appearance).
D=$WORK/sparky-stereo-look-qplatinum
T=$D/$LNF/org.sparkystereo.qplatinum
mkdir -p "$T/contents" "$D/usr/share/plasma/desktoptheme" "$D/usr/share/aurorae/themes" \
	"$D/usr/share/color-schemes"
cp "$HERE/qplatinum/org.sparkystereo.qplatinum/metadata.json" "$T/"
cp "$HERE/qplatinum/org.sparkystereo.qplatinum/contents/defaults" "$T/contents/"
cp -a "$SB/contents/splash" "$T/contents/"
cp "$HERE/sparkyblack/splash/Splash.qml" "$T/contents/splash/Splash.qml"   # bottomRect fix
cp -a "$QP" "$D/usr/share/plasma/desktoptheme/"
cp -a "$QPDECO" "$D/usr/share/aurorae/themes/"
cp "$QP"/color-schemes/*.colors "$D/usr/share/color-schemes/"
control "$D" sparky-stereo-look-qplatinum \
	"sparky-stereo-look-sparkyblack, kwin-style-aurorae, qt6ct" "" \
	"QPlatinum look: the System 8 Platinum appearance" \
	"Zinjanthr0pus's QPlatinum Plasma style and colour schemes and the" \
	"QPlatinum22p window decoration, as a global theme with Sparky black's" \
	"icons, cursor and splash."
cat >"$D/usr/share/doc/sparky-stereo-look-qplatinum/copyright" <<'EOF'
QPlatinum look.
QPlatinum Plasma style and colour schemes: Copyright Zinjanthr0pus, AGPL-3.0 (the LICENSE
file in /usr/share/plasma/desktoptheme/QPlatinum; its metadata says GPLv3).
QPlatinum22p window decoration: Niels / Zinjanthr0pus, GPL-3.0
(https://github.com/nielsvm/kde-aurorae-platinum; LICENSE in its theme folder).
Global theme definition: Copyright 2026 Daniel Ramos (Capitain Jack), GPL-3.0-or-later.
EOF
build "$D" sparky-stereo-look-qplatinum

# 4. Kubabbar Glass is built from its own source since milestone 2: ../kubabbar-glass/tools/build_packages.sh
#    (sparky-stereo-look-kubabbar-glass and sparky-stereo-gtk).

