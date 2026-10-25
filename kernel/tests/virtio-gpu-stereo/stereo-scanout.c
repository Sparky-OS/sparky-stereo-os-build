// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * stereo-scanout: lists the modes of the first connector of /dev/dri/card0 with their HDMI 3D structure (the
 * DRM_MODE_FLAG_3D_* bits, with DRM_CLIENT_CAP_STEREO_3D set), then sets, one after the other, the first mode of each
 * 3D structure on a dumb framebuffer, and a 2D mode last. On virtio-gpu with VIRTIO_GPU_F_STEREO every set sends
 * VIRTIO_GPU_CMD_SET_SCANOUT_STEREO (series groups 33 and 34), which the edition's QEMU traces.
 * Output, one line each: MODE|index|name|hdisplay|vdisplay|vrefresh|3d, SET|3d|hdisplay|vdisplay|fb_w|fb_h|rc.
 */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <drm/drm.h>
#include <drm/drm_mode.h>

static int fd;

static int ioc(unsigned long req, void *arg)
{
	int r;

	do {
		r = ioctl(fd, req, arg);
	} while (r < 0 && (errno == EINTR || errno == EAGAIN));
	return r < 0 ? -errno : 0;
}

static int set(__u32 crtc, __u32 conn, struct drm_mode_modeinfo *m)
{
	struct drm_mode_create_dumb dumb = { 0 };
	struct drm_mode_fb_cmd fb = { 0 };
	struct drm_mode_crtc c = { 0 };
	unsigned int s = (m->flags & DRM_MODE_FLAG_3D_MASK) >> 14;
	int rc;

	/* big enough for any stereo raster (drm_mode_set_crtcinfo with CRTC_STEREO_DOUBLE): both totals doubled */
	dumb.width = 2 * m->htotal;
	dumb.height = 2 * m->vtotal;
	dumb.bpp = 32;
	rc = ioc(DRM_IOCTL_MODE_CREATE_DUMB, &dumb);
	if (!rc) {
		fb.width = dumb.width;
		fb.height = dumb.height;
		fb.bpp = 32;
		fb.depth = 24;
		fb.pitch = dumb.pitch;
		fb.handle = dumb.handle;
		rc = ioc(DRM_IOCTL_MODE_ADDFB, &fb);
	}
	if (!rc) {
		c.crtc_id = crtc;
		c.fb_id = fb.fb_id;
		c.set_connectors_ptr = (unsigned long)&conn;
		c.count_connectors = 1;
		c.mode = *m;
		c.mode_valid = 1;
		rc = ioc(DRM_IOCTL_MODE_SETCRTC, &c);
	}
	printf("SET|%u|%u|%u|%u|%u|%d\n", s, m->hdisplay, m->vdisplay, dumb.width, dumb.height, rc);
	fflush(stdout);
	sleep(1);
	return rc;
}

int main(void)
{
	struct drm_set_client_cap cap = { DRM_CLIENT_CAP_STEREO_3D, 1 };
	struct drm_mode_card_res res = { 0 };
	struct drm_mode_get_connector conn = { 0 };
	__u32 crtcs[8], conns[8], encs[8];
	struct drm_mode_modeinfo *modes;
	int done[16] = { 0 };
	unsigned int i;

	fd = open("/dev/dri/card0", O_RDWR | O_CLOEXEC);
	if (fd < 0 || ioc(DRM_IOCTL_SET_CLIENT_CAP, &cap)) {
		printf("ERROR|open or stereo client cap: %s\n", strerror(errno));
		return 1;
	}
	res.crtc_id_ptr = (unsigned long)crtcs;
	res.connector_id_ptr = (unsigned long)conns;
	res.encoder_id_ptr = (unsigned long)encs;
	res.count_crtcs = res.count_connectors = res.count_encoders = 8;
	if (ioc(DRM_IOCTL_MODE_GETRESOURCES, &res) || !res.count_crtcs || !res.count_connectors) {
		printf("ERROR|no crtc or connector\n");
		return 1;
	}
	conn.connector_id = conns[0];
	if (ioc(DRM_IOCTL_MODE_GETCONNECTOR, &conn)) /* first call: the counts, and the mode probe */
		return 1;
	modes = calloc(conn.count_modes ? conn.count_modes : 1, sizeof(*modes));
	conn.modes_ptr = (unsigned long)modes;
	conn.count_props = conn.count_encoders = 0;
	if (ioc(DRM_IOCTL_MODE_GETCONNECTOR, &conn))
		return 1;
	for (i = 0; i < conn.count_modes; i++)
		printf("MODE|%u|%s|%u|%u|%u|%u\n", i, modes[i].name, modes[i].hdisplay, modes[i].vdisplay,
		       modes[i].vrefresh, (modes[i].flags & DRM_MODE_FLAG_3D_MASK) >> 14);
	for (i = 0; i < conn.count_modes; i++) {
		unsigned int s = (modes[i].flags & DRM_MODE_FLAG_3D_MASK) >> 14;

		if (s && s < 16 && !done[s]) {
			done[s] = 1;
			set(crtcs[0], conns[0], &modes[i]);
		}
	}
	for (i = 0; i < conn.count_modes; i++)
		if (!(modes[i].flags & DRM_MODE_FLAG_3D_MASK)) {
			set(crtcs[0], conns[0], &modes[i]);
			break;
		}
	printf("DONE|%u modes\n", conn.count_modes);
	return 0;
}
