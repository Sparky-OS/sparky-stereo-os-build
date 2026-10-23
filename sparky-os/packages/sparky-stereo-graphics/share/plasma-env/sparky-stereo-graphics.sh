# Created by Daniel Ramos (Capitain Jack) 2026/10/23
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/23
# Sourced by startplasma before sparky-stereo-primary-gpu.sh. The main desktop GPU the person chose
# in System Settings, Graphics becomes KWIN_DRM_DEVICES at this login. Automatic sets nothing, so
# the edition's own rule in sparky-stereo-primary-gpu.sh and KWin's order stay in charge. A
# KWIN_DRM_DEVICES the person set by hand, here or in ~/.config/plasma-workspace/env, wins.
if [ -z "${KWIN_DRM_DEVICES:-}" ] && command -v sparky-stereo-gpu-env >/dev/null 2>&1; then
	_sp_graphics=$(sparky-stereo-gpu-env --session 2>/dev/null)
	if [ -n "$_sp_graphics" ]; then
		eval "$_sp_graphics"
	fi
	unset _sp_graphics
fi
