#!/bin/bash
# runs the probe (or another program: PROG) with the Wayland protocol trace filtered to what matters
export QT_QPA_PLATFORM=wayland WAYLAND_DEBUG=client LIBGL_ALWAYS_SOFTWARE=1 QT_LOGGING_RULES='*.debug=false'
exec ${PROG:-/w/bin/probe} 2>&1 | grep --line-buffered -E "kde_stereo|get_subsurface|place_below|set_destination|wl_subsurface.*set_position|app_id|^probe|^marble|rror" 
