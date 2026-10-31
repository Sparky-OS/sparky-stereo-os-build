/* SPDX-License-Identifier: LGPL-2.1-or-later */
#include "fu-volume-locker.h"

static gboolean cached_mounted;
static gboolean actual_mounted;
static gboolean mount_fails;
static guint mounts;
static guint unmounts;

gboolean
fu_volume_is_mounted(FuVolume *volume)
{
	(void)volume;
	return cached_mounted;
}

gboolean
fu_volume_mount(FuVolume *volume, GError **error)
{
	(void)volume;
	mounts++;
	if (mount_fails) {
		g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_FAILED, "injected mount failure");
		return FALSE;
	}
	actual_mounted = TRUE;
	return TRUE;
}

gboolean
fu_volume_unmount(FuVolume *volume, GError **error)
{
	(void)volume;
	(void)error;
	unmounts++;
	actual_mounted = FALSE;
	return TRUE;
}

int
main(int argc, char **argv)
{
	g_autoptr(GObject) volume = g_object_new(G_TYPE_OBJECT, NULL);
	g_autoptr(FuVolumeLocker) locker = NULL;
	g_autoptr(GError) error = NULL;
	gboolean explicit_close;
	gboolean expected_mounted;
	gboolean pass;
	guint expected_mounts;
	guint expected_unmounts;

	if (argc != 2)
		return 2;
	cached_mounted = g_str_equal(argv[1], "external-mounted");
	actual_mounted = cached_mounted || g_str_equal(argv[1], "external-stale-cache");
	mount_fails = g_str_equal(argv[1], "mount-failure") ||
		      g_str_equal(argv[1], "external-stale-cache");
	explicit_close = g_str_equal(argv[1], "owned-explicit-close");
	expected_mounted = actual_mounted;
	expected_mounts = cached_mounted ? 0 : 1;
	expected_unmounts = (!cached_mounted && !mount_fails) ? 1 : 0;

	locker = fu_volume_locker_new(volume, &error);
	pass = mount_fails ? (locker == NULL && error != NULL) :
			    (locker != NULL && error == NULL);
	if (explicit_close && locker != NULL) {
		pass &= fu_volume_locker_close(locker, &error);
		pass &= fu_volume_locker_close(locker, &error);
	}
	g_clear_object(&locker);
	pass &= mounts == expected_mounts;
	pass &= unmounts == expected_unmounts;
	pass &= actual_mounted == expected_mounted;
	g_print("%s %s: mounts=%u/%u unmounts=%u/%u mounted=%u/%u\n",
		pass ? "PASS" : "FAIL", argv[1], mounts, expected_mounts,
		unmounts, expected_unmounts, actual_mounted, expected_mounted);
	return pass ? 0 : 1;
}
