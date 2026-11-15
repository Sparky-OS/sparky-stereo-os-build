# Created by Daniel Ramos (Capitain Jack) 2026/11/14
# Copyright 2026 under the GNU GPL3 License
# Sourced by startplasma, before KWin starts. On a computer with a touch screen of its own (a touch screen and a
# built-in panel: a convertible, a slider, a detachable, a tablet, a notebook with a touch screen) KDE's on-screen
# keyboard is the virtual keyboard by default, so it appears on a text field touched in tablet mode with nobody
# choosing it in System Settings. KWin shows it only in tablet mode unless the person switches that off.
# The default is a system default, never a line in the person's own files: a folder with one kwinrc goes in front of
# XDG_CONFIG_DIRS, where KConfig reads it below the person's ~/.config/kwinrc. System Settings, Virtual Keyboard then
# shows it as the default, and a keyboard the person chooses there, or None, is written to their own file and wins.
# The keyboard's layout is the session's language: Plasma Keyboard takes the locale when no language was chosen in its
# own page. A computer without a touch screen of its own gets nothing of this.
_sp_tablet=${SPARKY_STEREO_TABLET_MODE_DIR:-/usr/share/sparky-stereo-hardware/tablet-mode/xdg}
if "${SPARKY_STEREO_HAS_TABLET_MODE:-/usr/lib/sparky-stereo-hardware/has-tablet-mode}"; then
	case ":${XDG_CONFIG_DIRS:-/etc/xdg}:" in
	*":$_sp_tablet:"*) ;;
	*)
		XDG_CONFIG_DIRS=$_sp_tablet:${XDG_CONFIG_DIRS:-/etc/xdg}
		export XDG_CONFIG_DIRS
		;;
	esac
fi
unset _sp_tablet
