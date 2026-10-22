// SPDX-License-Identifier: GPL-2.0
/*
 * edid3d: feed a test EDID (edid_blob.h, made by make_edid.py) to the DRM core's EDID parser on a throw-away connector and print the modes it lists, with their stereo
 * 3D layout and the CRTC timings drm_mode_set_crtcinfo(CRTC_STEREO_DOUBLE) works out for them. Output goes to the kernel log as lines "EDID3D|...". The module does its
 * work in init and returns an error so that it never stays loaded.
 */
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/slab.h>
#include <drm/drm_connector.h>
#include <drm/drm_drv.h>
#include <drm/drm_edid.h>
#include <drm/drm_mode_config.h>
#include <drm/drm_modes.h>
#include <uapi/drm/drm_mode.h>

#include "edid_blob.h"

static const struct drm_driver edid3d_driver = {
	.driver_features = DRIVER_MODESET,
	.name = "edid3d",
	.desc = "EDID 3D mode listing test",
	.major = 1,
	.minor = 0,
};

static void edid3d_conn_destroy(struct drm_connector *c)
{
	drm_connector_cleanup(c);
	kfree(c);
}

static const struct drm_connector_funcs edid3d_conn_funcs = {
	.destroy = edid3d_conn_destroy,
};

static int __init edid3d_init(void)
{
	struct platform_device *pdev;
	struct drm_device *drm;
	struct drm_connector *conn;
	const struct drm_edid *edid;
	struct drm_display_mode *m;
	int ret, n = 0;

	pdev = platform_device_register_simple("edid3d", PLATFORM_DEVID_NONE, NULL, 0);
	if (IS_ERR(pdev))
		return PTR_ERR(pdev);

	drm = drm_dev_alloc(&edid3d_driver, &pdev->dev);
	if (IS_ERR(drm)) {
		ret = PTR_ERR(drm);
		goto out_pdev;
	}
	ret = drmm_mode_config_init(drm);
	if (ret)
		goto out_drm;
	drm->mode_config.min_width = 0;
	drm->mode_config.min_height = 0;
	drm->mode_config.max_width = 16384;
	drm->mode_config.max_height = 16384;

	conn = kzalloc(sizeof(*conn), GFP_KERNEL);
	if (!conn) {
		ret = -ENOMEM;
		goto out_drm;
	}
	ret = drm_connector_init(drm, conn, &edid3d_conn_funcs, DRM_MODE_CONNECTOR_HDMIA);
	if (ret) {
		kfree(conn);
		goto out_drm;
	}

	edid = drm_edid_alloc(edid_blob, sizeof(edid_blob));
	if (!edid) {
		ret = -ENOMEM;
		goto out_drm;
	}
	ret = drm_edid_connector_update(conn, edid);
	pr_info("EDID3D|update|rc=%d|is_hdmi=%d|has_audio=%d|max_tmds_khz=%d\n", ret, conn->display_info.is_hdmi, conn->display_info.has_audio,
		conn->display_info.max_tmds_clock);
	ret = drm_edid_connector_add_modes(conn);
	pr_info("EDID3D|add_modes|returned=%d\n", ret);

	list_for_each_entry(m, &conn->probed_modes, head) {
		struct drm_display_mode t = *m;

		drm_mode_set_crtcinfo(&t, CRTC_STEREO_DOUBLE);
		/* hdisplay|vdisplay|refresh|interlaced|3d layout|clock|htotal|vtotal|crtc_clock|crtc_hdisplay|crtc_htotal|crtc_vdisplay|crtc_vtotal */
		pr_info("EDID3D|mode|%d|%d|%d|%d|%u|%d|%d|%d|%d|%d|%d|%d|%d\n", m->hdisplay, m->vdisplay, drm_mode_vrefresh(m), !!(m->flags & DRM_MODE_FLAG_INTERLACE),
			(m->flags & DRM_MODE_FLAG_3D_MASK) >> 14, m->clock, m->htotal, m->vtotal, t.crtc_clock, t.crtc_hdisplay, t.crtc_htotal, t.crtc_vdisplay, t.crtc_vtotal);
		n++;
	}
	pr_info("EDID3D|done|modes=%d\n", n);
	drm_edid_free(edid);
	ret = -ENODEV;			/* never stay loaded */
out_drm:
	drm_dev_put(drm);
out_pdev:
	platform_device_unregister(pdev);
	return ret;
}

module_init(edid3d_init);
MODULE_DESCRIPTION("Lists the modes the DRM EDID parser makes of a test EDID with HDMI 3D support");
MODULE_LICENSE("GPL");
