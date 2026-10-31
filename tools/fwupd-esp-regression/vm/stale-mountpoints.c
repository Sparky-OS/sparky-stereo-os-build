/* SPDX-License-Identifier: LGPL-2.1-or-later */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <gio/gio.h>
#include <stdio.h>
#include <string.h>

/* Fault injection only: hide the cached mount state, not the real mount. */
GVariant *
g_dbus_proxy_get_cached_property(GDBusProxy *proxy, const gchar *name)
{
	typedef GVariant *(*GetProperty)(GDBusProxy *, const gchar *);
	GetProperty original = (GetProperty)dlsym(RTLD_NEXT, "g_dbus_proxy_get_cached_property");
	if (g_strcmp0(g_dbus_proxy_get_interface_name(proxy),
		      "org.freedesktop.UDisks2.Filesystem") == 0 &&
	    g_strcmp0(name, "MountPoints") == 0) {
		fprintf(stderr, "INJECT stale MountPoints %s\n", g_dbus_proxy_get_object_path(proxy));
		return g_variant_ref_sink(g_variant_new_bytestring_array(NULL, 0));
	}
	return original(proxy, name);
}

GVariant *
g_dbus_proxy_call_sync(GDBusProxy *proxy, const gchar *method, GVariant *parameters,
		      GDBusCallFlags flags, gint timeout, GCancellable *cancel, GError **error)
{
	typedef GVariant *(*Call)(GDBusProxy *, const gchar *, GVariant *, GDBusCallFlags,
				gint, GCancellable *, GError **);
	Call original = (Call)dlsym(RTLD_NEXT, "g_dbus_proxy_call_sync");
	gboolean tracked = g_strcmp0(g_dbus_proxy_get_interface_name(proxy),
				   "org.freedesktop.UDisks2.Filesystem") == 0 &&
			   (g_strcmp0(method, "Mount") == 0 || g_strcmp0(method, "Unmount") == 0);
	if (tracked)
		fprintf(stderr, "UDISKS CALL %s %s\n", method, g_dbus_proxy_get_object_path(proxy));
	GVariant *reply = original(proxy, method, parameters, flags, timeout, cancel, error);
	if (tracked) {
		g_autofree gchar *remote = error != NULL && *error != NULL ?
			g_dbus_error_get_remote_error(*error) : NULL;
		fprintf(stderr, "UDISKS REPLY %s %s\n", method,
			reply != NULL ? "OK" : (remote != NULL ? remote : "ERROR"));
	}
	return reply;
}
