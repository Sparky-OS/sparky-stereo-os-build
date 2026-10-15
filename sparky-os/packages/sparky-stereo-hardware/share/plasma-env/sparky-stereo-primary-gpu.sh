# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/15
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/15
# Sourced by startplasma. KWin renders on the firmware's boot VGA device. On server and workstation
# boards that is often the BMC's small VGA chip, which cannot render, while the real graphics card
# drives the screens. Then the cards that can render (they have a render node) go first, those with
# a screen connected before the others, so KWin renders on the card the screens are on.
# A KWIN_DRM_DEVICES set by the person is kept.
if [ -z "${KWIN_DRM_DEVICES:-}" ]; then
	_sp_boot= _sp_first= _sp_second= _sp_rest= _sp_c= _sp_render= _sp_conn= _sp_s= _sp_dev=
	for _sp_c in ${SPARKY_STEREO_SYSFS:-/sys}/class/drm/card[0-9]*; do
		case ${_sp_c##*/} in *-*) continue ;; esac
		[ -e "$_sp_c/device" ] || continue
		_sp_render=0 _sp_conn=0
		ls "$_sp_c/device/drm" 2>/dev/null | grep -q '^renderD' && _sp_render=1
		for _sp_s in "$_sp_c"-*/status; do
			[ "$(cat "$_sp_s" 2>/dev/null)" = connected ] && _sp_conn=1
		done
		[ "$(cat "$_sp_c/device/boot_vga" 2>/dev/null)" = 1 ] && _sp_boot=$_sp_render
		_sp_dev=/dev/dri/${_sp_c##*/}
		if [ $_sp_render = 1 ] && [ $_sp_conn = 1 ]; then
			_sp_first="$_sp_first:$_sp_dev"
		elif [ $_sp_render = 1 ]; then
			_sp_second="$_sp_second:$_sp_dev"
		else
			_sp_rest="$_sp_rest:$_sp_dev"
		fi
	done
	if [ "$_sp_boot" = 0 ] && [ -n "$_sp_first$_sp_second" ]; then
		KWIN_DRM_DEVICES=$(echo "$_sp_first$_sp_second$_sp_rest" | sed 's/^://')
		export KWIN_DRM_DEVICES
	fi
	unset _sp_boot _sp_first _sp_second _sp_rest _sp_c _sp_render _sp_conn _sp_s _sp_dev
fi
