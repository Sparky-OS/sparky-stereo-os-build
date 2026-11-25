# Created by Daniel Ramos (Capitain Jack) 2026/11/25
# Copyright 2026 under the GNU GPL3 License
# Sourced by startplasma after sparky-stereo-hardware's sparky-stereo-tablet-mode.sh (the names sort so). Where the
# hardware layer found a touch screen of the computer's own, its folder is then in front of XDG_CONFIG_DIRS; here the
# Welcome Center is told so with a folder of its own in front of it too, holding a plasma-welcomerc that sets
# [Distribution] TouchScreen=true, which KConfig reads below the person's own ~/.config/plasma-welcomerc. The touch page
# reads it (Welcome.Distro.flag) when it is shown only on such a computer. Elsewhere nothing is set.
_sp_hardware=${SPARKY_STEREO_TABLET_MODE_DIR:-/usr/share/sparky-stereo-hardware/tablet-mode/xdg}
_sp_welcome=/usr/share/sparky-stereo-welcome/touch-screen/xdg
case ":${XDG_CONFIG_DIRS:-/etc/xdg}:" in
*":$_sp_hardware:"*)
	case ":$XDG_CONFIG_DIRS:" in
	*":$_sp_welcome:"*) ;;
	*)
		XDG_CONFIG_DIRS=$_sp_welcome:$XDG_CONFIG_DIRS
		export XDG_CONFIG_DIRS
		;;
	esac
	;;
esac
unset _sp_hardware _sp_welcome
