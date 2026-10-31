/* SPDX-License-Identifier: LGPL-2.1-or-later */
#pragma once
#include <gio/gio.h>
#include "fwupd-build.h"
typedef GObject FuVolume;
#define FU_IS_VOLUME G_IS_OBJECT
#define FWUPD_ERROR (g_quark_from_static_string("fwupd-test-error"))
#define FWUPD_ERROR_NOT_FOUND 1
#define FWUPD_ERROR_NOTHING_TO_DO 2
gboolean fu_volume_is_mounted(FuVolume *volume);
gboolean fu_volume_mount(FuVolume *volume, GError **error);
gboolean fu_volume_unmount(FuVolume *volume, GError **error);
