# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/16
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/16
# Sourced by startplasma. When NVIDIA's driver runs the desktop and the system default is zink
# (/etc/sparky-stereo/opengl-stereo.conf, written by sparky-stereo-opengl-default), the
# programs of the session run their OpenGL on Mesa over NVIDIA's Vulkan driver, where a program
# that draws its own two views gets them, from the menu, the panel or a terminal alike:
#   Mesa's EGL vendor first and NVIDIA's second (NVIDIA's Vulkan driver does not start without
#   its own EGL vendor), Mesa's GLX, zink, and Mesa's own presentation path, which carries the
#   two views (LIBGL_KOPPER_DISABLE: zink's Vulkan swapchain path has none yet).
# KWin and its Xwayland keep NVIDIA's driver: plasma-kwin_wayland.service drops these variables.
# Nothing is set when the session does not start KWin through systemd, or when the person set
# an EGL vendor list or a Mesa driver of their own. GL_STEREO_NVIDIA_OPENGL gives gl-stereo-run
# the system choice as its default.
_sp_conf=${SPARKY_STEREO_OPENGL_CONF:-/etc/sparky-stereo/opengl-stereo.conf}
if [ -r "$_sp_conf" ] && [ "$(sed -n 's/^desktop=//p' "$_sp_conf" | tail -n1)" = nvidia ]; then
	_sp_gl=$(sed -n 's/^opengl=\(zink\|nvidia\)$/\1/p' "$_sp_conf" | tail -n1)
	_sp_gl=${_sp_gl:-zink}
	[ -n "${GL_STEREO_NVIDIA_OPENGL:-}" ] || export GL_STEREO_NVIDIA_OPENGL=$_sp_gl
	_sp_vendors=${SPARKY_STEREO_EGL_VENDORS:-/usr/share/glvnd/egl_vendor.d}
	_sp_systemd=$(kreadconfig6 --file startkderc --group General --key systemdBoot --default true 2>/dev/null || echo true)
	if [ "$_sp_gl" = zink ] && [ "$_sp_systemd" != false ] &&
		[ -f "$_sp_vendors/50_mesa.json" ] && [ -f "$_sp_vendors/10_nvidia.json" ] &&
		[ -z "${__EGL_VENDOR_LIBRARY_FILENAMES:-}${MESA_LOADER_DRIVER_OVERRIDE:-}" ]; then
		export SPARKY_STEREO_OPENGL=zink
		export __EGL_VENDOR_LIBRARY_FILENAMES="$_sp_vendors/50_mesa.json:$_sp_vendors/10_nvidia.json"
		export __GLX_VENDOR_LIBRARY_NAME=mesa
		export MESA_LOADER_DRIVER_OVERRIDE=zink
		export LIBGL_KOPPER_DISABLE=1
	fi
	unset _sp_gl _sp_vendors _sp_systemd
fi
unset _sp_conf
