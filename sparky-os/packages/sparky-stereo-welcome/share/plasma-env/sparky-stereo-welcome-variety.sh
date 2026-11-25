# Created by Daniel Ramos (Capitain Jack) 2026/11/25
# Copyright 2026 under the GNU GPL3 License
# Sourced by startplasma. Where Stereo Variety is installed, the Welcome Center is told so with a folder of its own in
# front of XDG_CONFIG_DIRS, holding a plasma-welcomerc that sets [Distribution] Variety=true, which KConfig reads below the
# person's own ~/.config/plasma-welcomerc. The wallpaper page reads it (Welcome.Distro.flag) and is shown only there.
# Elsewhere nothing is set.
_sp_variety=${SPARKY_STEREO_VARIETY:-/usr/bin/variety}
_sp_welcome=/usr/share/sparky-stereo-welcome/variety/xdg
if [ -x "$_sp_variety" ]; then
	case ":${XDG_CONFIG_DIRS:-}:" in
	*":$_sp_welcome:"*) ;;
	*)
		XDG_CONFIG_DIRS=$_sp_welcome:${XDG_CONFIG_DIRS:-/etc/xdg}
		export XDG_CONFIG_DIRS
		;;
	esac
fi
unset _sp_variety _sp_welcome
