// SPDX-License-Identifier: MIT
/*
 * fs-probe: frame-sequential stereo (DRM_MODE_FLAG_3D_FRAME_SEQUENTIAL) on one
 * connector, checked frame by frame through the CRTC's CRC.
 *
 *   fs-probe list CARD                 connectors, their status and stereo modes
 *   fs-probe test CARD CONNECTOR       TEST_ONLY commit of the connector's
 *                                      frame-sequential mode (declared, or the
 *                                      twin of its preferred 2D mode)
 *   fs-probe run CARD CONNECTOR        the CRC runs below, then the debugfs
 *                                      stereo_state, then exit (the console
 *                                      restores its own mode)
 *
 * CARD is a number (0 for /dev/dri/card0). "run" needs to be DRM master (no
 * compositor on the card) and root (debugfs). It only touches the CRTC, the
 * primary plane and the connector it uses; it never sets a mode on any other
 * connector.
 *
 * The runs:
 *  1. reference: the 2D mode with a framebuffer of one colour, once per colour,
 *     gives each colour's CRC;
 *  2. alternation: the frame-sequential mode with a side by side framebuffer,
 *     left half one colour and right half another; every frame's CRC must be
 *     one eye's and the eyes must take turns;
 *  3. flips: two side by side framebuffers with four colours, flipped one
 *     after the other; a left-eye frame and the right-eye frame after it must
 *     always come from the same framebuffer.
 *
 * Built static from the kernel's uAPI headers only; no libdrm. FS_PROBE_DEBUG=1
 * also prints every CRC of the reference runs.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <drm/drm.h>
#include <drm/drm_mode.h>

#ifndef DRM_MODE_FLAG_3D_FRAME_SEQUENTIAL
#define DRM_MODE_FLAG_3D_FRAME_SEQUENTIAL (9 << 14)
#endif
#define DRM_FORMAT_XRGB8888 0x34325258 /* 'XR24' */
/* values of the plane "type" property: Overlay 0, Primary 1, Cursor 2 */
#define PLANE_TYPE_PRIMARY 1

#define MAX_IDS 64
#define CRC_MAX 128 /* DRM_CRC_ENTRIES_NR */

static int fd = -1;
static int card;

static void *xcalloc(size_t n, size_t s)
{
	void *p = calloc(n ? n : 1, s);

	if (!p) {
		perror("calloc");
		exit(2);
	}
	return p;
}

static int xioctl(unsigned long req, void *arg)
{
	int ret;

	do {
		ret = ioctl(fd, req, arg);
	} while (ret == -1 && (errno == EINTR || errno == EAGAIN));
	return ret;
}

static const char *connector_type_name(uint32_t type)
{
	static const char *const names[] = {
		[DRM_MODE_CONNECTOR_Unknown] = "Unknown",
		[DRM_MODE_CONNECTOR_VGA] = "VGA",
		[DRM_MODE_CONNECTOR_DVII] = "DVI-I",
		[DRM_MODE_CONNECTOR_DVID] = "DVI-D",
		[DRM_MODE_CONNECTOR_DVIA] = "DVI-A",
		[DRM_MODE_CONNECTOR_Composite] = "Composite",
		[DRM_MODE_CONNECTOR_SVIDEO] = "SVIDEO",
		[DRM_MODE_CONNECTOR_LVDS] = "LVDS",
		[DRM_MODE_CONNECTOR_Component] = "Component",
		[DRM_MODE_CONNECTOR_9PinDIN] = "DIN",
		[DRM_MODE_CONNECTOR_DisplayPort] = "DP",
		[DRM_MODE_CONNECTOR_HDMIA] = "HDMI-A",
		[DRM_MODE_CONNECTOR_HDMIB] = "HDMI-B",
		[DRM_MODE_CONNECTOR_TV] = "TV",
		[DRM_MODE_CONNECTOR_eDP] = "eDP",
		[DRM_MODE_CONNECTOR_VIRTUAL] = "Virtual",
		[DRM_MODE_CONNECTOR_DSI] = "DSI",
		[DRM_MODE_CONNECTOR_DPI] = "DPI",
		[DRM_MODE_CONNECTOR_WRITEBACK] = "Writeback",
	};

	return type < sizeof(names) / sizeof(names[0]) && names[type] ? names[type] : "Unknown";
}

/* --- objects ------------------------------------------------------------ */

struct connector {
	uint32_t id, type, type_id, connection, encoder_id;
	uint32_t encoders[MAX_IDS];
	uint32_t count_encoders;
	struct drm_mode_modeinfo *modes;
	uint32_t count_modes;
	char name[32];
};

static void get_connector(uint32_t id, struct connector *c)
{
	struct drm_mode_get_connector gc;

	memset(c, 0, sizeof(*c));
	memset(&gc, 0, sizeof(gc));
	gc.connector_id = id;
	if (xioctl(DRM_IOCTL_MODE_GETCONNECTOR, &gc)) {
		perror("GETCONNECTOR");
		exit(2);
	}
	c->modes = xcalloc(gc.count_modes, sizeof(*c->modes));
	if (gc.count_encoders > MAX_IDS)
		gc.count_encoders = MAX_IDS;
	gc.modes_ptr = (uintptr_t)c->modes;
	gc.encoders_ptr = (uintptr_t)c->encoders;
	gc.count_props = 0;
	if (xioctl(DRM_IOCTL_MODE_GETCONNECTOR, &gc)) {
		perror("GETCONNECTOR");
		exit(2);
	}
	c->id = id;
	c->type = gc.connector_type;
	c->type_id = gc.connector_type_id;
	c->connection = gc.connection;
	c->encoder_id = gc.encoder_id;
	c->count_encoders = gc.count_encoders;
	c->count_modes = gc.count_modes;
	snprintf(c->name, sizeof(c->name), "%s-%u", connector_type_name(c->type), c->type_id);
}

static struct drm_mode_card_res res;
static uint32_t crtc_ids[MAX_IDS], connector_ids[MAX_IDS], encoder_ids[MAX_IDS];

static void get_resources(void)
{
	memset(&res, 0, sizeof(res));
	if (xioctl(DRM_IOCTL_MODE_GETRESOURCES, &res)) {
		perror("GETRESOURCES");
		exit(2);
	}
	if (res.count_crtcs > MAX_IDS || res.count_connectors > MAX_IDS ||
	    res.count_encoders > MAX_IDS) {
		fprintf(stderr, "too many objects\n");
		exit(2);
	}
	res.count_fbs = 0;
	res.crtc_id_ptr = (uintptr_t)crtc_ids;
	res.connector_id_ptr = (uintptr_t)connector_ids;
	res.encoder_id_ptr = (uintptr_t)encoder_ids;
	if (xioctl(DRM_IOCTL_MODE_GETRESOURCES, &res)) {
		perror("GETRESOURCES");
		exit(2);
	}
}

static uint32_t prop_id(uint32_t obj, uint32_t type, const char *name)
{
	struct drm_mode_obj_get_properties gp;
	uint32_t ids[128];
	uint64_t vals[128];
	uint32_t i;

	memset(&gp, 0, sizeof(gp));
	gp.obj_id = obj;
	gp.obj_type = type;
	gp.props_ptr = (uintptr_t)ids;
	gp.prop_values_ptr = (uintptr_t)vals;
	gp.count_props = 128;
	if (xioctl(DRM_IOCTL_MODE_OBJ_GETPROPERTIES, &gp)) {
		perror("OBJ_GETPROPERTIES");
		exit(2);
	}
	for (i = 0; i < gp.count_props && i < 128; i++) {
		struct drm_mode_get_property p;

		memset(&p, 0, sizeof(p));
		p.prop_id = ids[i];
		if (xioctl(DRM_IOCTL_MODE_GETPROPERTY, &p))
			continue;
		if (!strcmp(p.name, name))
			return ids[i];
	}
	fprintf(stderr, "object %u has no property %s\n", obj, name);
	exit(2);
}

static uint64_t prop_value(uint32_t obj, uint32_t type, const char *name)
{
	struct drm_mode_obj_get_properties gp;
	uint32_t ids[128], want = prop_id(obj, type, name), i;
	uint64_t vals[128];

	memset(&gp, 0, sizeof(gp));
	gp.obj_id = obj;
	gp.obj_type = type;
	gp.props_ptr = (uintptr_t)ids;
	gp.prop_values_ptr = (uintptr_t)vals;
	gp.count_props = 128;
	if (xioctl(DRM_IOCTL_MODE_OBJ_GETPROPERTIES, &gp))
		return 0;
	for (i = 0; i < gp.count_props && i < 128; i++)
		if (ids[i] == want)
			return vals[i];
	return 0;
}

static int find_connector(const char *name, struct connector *out)
{
	uint32_t i;

	for (i = 0; i < res.count_connectors; i++) {
		get_connector(connector_ids[i], out);
		if (!strcmp(out->name, name))
			return 0;
		free(out->modes);
	}
	return -1;
}

/* the CRTC the connector drives now, or the first one its encoders can use */
static int find_crtc(const struct connector *c, uint32_t *crtc_id, int *crtc_index)
{
	uint32_t i, j;

	for (i = 0; i < c->count_encoders; i++) {
		struct drm_mode_get_encoder ge;

		memset(&ge, 0, sizeof(ge));
		ge.encoder_id = c->encoders[i];
		if (xioctl(DRM_IOCTL_MODE_GETENCODER, &ge))
			continue;
		if (ge.encoder_id == c->encoder_id && ge.crtc_id) {
			for (j = 0; j < res.count_crtcs; j++)
				if (crtc_ids[j] == ge.crtc_id) {
					*crtc_id = ge.crtc_id;
					*crtc_index = j;
					return 0;
				}
		}
	}
	for (i = 0; i < c->count_encoders; i++) {
		struct drm_mode_get_encoder ge;

		memset(&ge, 0, sizeof(ge));
		ge.encoder_id = c->encoders[i];
		if (xioctl(DRM_IOCTL_MODE_GETENCODER, &ge))
			continue;
		for (j = 0; j < res.count_crtcs; j++)
			if (ge.possible_crtcs & (1u << j)) {
				*crtc_id = crtc_ids[j];
				*crtc_index = j;
				return 0;
			}
	}
	return -1;
}

/* every plane: its id, type and current CRTC */
struct plane {
	uint32_t id, possible_crtcs, crtc_id;
	uint64_t type;
};

static int get_planes(struct plane *planes)
{
	struct drm_mode_get_plane_res pr;
	uint32_t ids[MAX_IDS], i;

	memset(&pr, 0, sizeof(pr));
	pr.plane_id_ptr = (uintptr_t)ids;
	pr.count_planes = MAX_IDS;
	if (xioctl(DRM_IOCTL_MODE_GETPLANERESOURCES, &pr)) {
		perror("GETPLANERESOURCES");
		exit(2);
	}
	for (i = 0; i < pr.count_planes && i < MAX_IDS; i++) {
		struct drm_mode_get_plane gp;

		memset(&gp, 0, sizeof(gp));
		gp.plane_id = ids[i];
		if (xioctl(DRM_IOCTL_MODE_GETPLANE, &gp)) {
			perror("GETPLANE");
			exit(2);
		}
		planes[i].id = ids[i];
		planes[i].possible_crtcs = gp.possible_crtcs;
		planes[i].crtc_id = gp.crtc_id;
		planes[i].type = prop_value(ids[i], DRM_MODE_OBJECT_PLANE, "type");
	}
	return i;
}

/* --- modes --------------------------------------------------------------- */

static bool mode_is_fs(const struct drm_mode_modeinfo *m)
{
	return (m->flags & DRM_MODE_FLAG_3D_MASK) == DRM_MODE_FLAG_3D_FRAME_SEQUENTIAL;
}

static unsigned int mode_hz(const struct drm_mode_modeinfo *m)
{
	return m->vrefresh ? m->vrefresh :
		(unsigned int)((m->clock * 1000ull) / ((uint64_t)m->htotal * m->vtotal));
}

static void print_mode(const char *what, const struct drm_mode_modeinfo *m)
{
	printf("%s %s %ux%u@%u clock %u kHz flags 0x%x%s\n", what, m->name, m->hdisplay,
	       m->vdisplay, mode_hz(m), m->clock, m->flags,
	       mode_is_fs(m) ? " (frame sequential)" :
	       (m->flags & DRM_MODE_FLAG_3D_MASK) ? " (other 3D)" : "");
}

/* a declared frame-sequential mode, else the preferred 2D mode with the flag */
static void pick_modes(const struct connector *c, struct drm_mode_modeinfo *mode2d,
		       struct drm_mode_modeinfo *modefs)
{
	const struct drm_mode_modeinfo *pref = NULL;
	uint32_t i;

	for (i = 0; i < c->count_modes; i++)
		if (mode_is_fs(&c->modes[i])) {
			*modefs = c->modes[i];
			*mode2d = c->modes[i];
			mode2d->flags &= ~DRM_MODE_FLAG_3D_MASK;
			printf("declared frame-sequential mode\n");
			return;
		}
	for (i = 0; i < c->count_modes; i++)
		if (!(c->modes[i].flags & DRM_MODE_FLAG_3D_MASK) &&
		    (c->modes[i].type & DRM_MODE_TYPE_PREFERRED) && !pref)
			pref = &c->modes[i];
	for (i = 0; !pref && i < c->count_modes; i++)
		if (!(c->modes[i].flags & DRM_MODE_FLAG_3D_MASK))
			pref = &c->modes[i];
	if (!pref) {
		fprintf(stderr, "%s has no 2D mode\n", c->name);
		exit(2);
	}
	*mode2d = *pref;
	*modefs = *pref;
	modefs->flags |= DRM_MODE_FLAG_3D_FRAME_SEQUENTIAL;
	modefs->type &= ~DRM_MODE_TYPE_PREFERRED;
	printf("twin of the preferred 2D mode\n");
}

/* --- framebuffers -------------------------------------------------------- */

struct fb {
	uint32_t id, handle, width, height, pitch;
	uint64_t size;
	uint32_t *map;
};

/* a linear XRGB8888 dumb buffer, left half @left, right half @right */
static void make_fb(struct fb *fb, uint32_t width, uint32_t height, uint32_t left, uint32_t right)
{
	struct drm_mode_create_dumb cd;
	struct drm_mode_map_dumb md;
	struct drm_mode_fb_cmd2 f;
	uint32_t x, y;

	memset(&cd, 0, sizeof(cd));
	cd.width = width;
	cd.height = height;
	cd.bpp = 32;
	if (xioctl(DRM_IOCTL_MODE_CREATE_DUMB, &cd)) {
		perror("CREATE_DUMB");
		exit(2);
	}
	memset(&md, 0, sizeof(md));
	md.handle = cd.handle;
	if (xioctl(DRM_IOCTL_MODE_MAP_DUMB, &md)) {
		perror("MAP_DUMB");
		exit(2);
	}
	fb->map = mmap(NULL, cd.size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, md.offset);
	if (fb->map == MAP_FAILED) {
		perror("mmap");
		exit(2);
	}
	for (y = 0; y < height; y++)
		for (x = 0; x < width; x++)
			fb->map[y * (cd.pitch / 4) + x] = x < width / 2 ? left : right;

	memset(&f, 0, sizeof(f));
	f.width = width;
	f.height = height;
	f.pixel_format = DRM_FORMAT_XRGB8888;
	f.handles[0] = cd.handle;
	f.pitches[0] = cd.pitch;
	if (xioctl(DRM_IOCTL_MODE_ADDFB2, &f)) {
		perror("ADDFB2");
		exit(2);
	}
	fb->id = f.fb_id;
	fb->handle = cd.handle;
	fb->width = width;
	fb->height = height;
	fb->pitch = cd.pitch;
	fb->size = cd.size;
}

/* --- atomic -------------------------------------------------------------- */

struct pipe {
	struct connector conn;
	uint32_t crtc_id, plane_id;
	int crtc_index;
	uint32_t other_planes[MAX_IDS];
	int count_other;
	struct {
		uint32_t conn_crtc, crtc_mode, crtc_active, fb, crtc, sx, sy, sw, sh, cx, cy, cw, ch;
	} p;
};

#define MAX_PROPS 64
struct req {
	uint32_t objs[8], counts[8], props[MAX_PROPS];
	uint64_t vals[MAX_PROPS];
	int nobj, nprop;
};

static void req_add(struct req *r, uint32_t obj, uint32_t prop, uint64_t val)
{
	if (!r->nobj || r->objs[r->nobj - 1] != obj) {
		r->objs[r->nobj] = obj;
		r->counts[r->nobj] = 0;
		r->nobj++;
	}
	r->counts[r->nobj - 1]++;
	r->props[r->nprop] = prop;
	r->vals[r->nprop] = val;
	r->nprop++;
}

static int req_commit(struct req *r, uint32_t flags)
{
	struct drm_mode_atomic a;

	memset(&a, 0, sizeof(a));
	a.flags = flags;
	a.count_objs = r->nobj;
	a.objs_ptr = (uintptr_t)r->objs;
	a.count_props_ptr = (uintptr_t)r->counts;
	a.props_ptr = (uintptr_t)r->props;
	a.prop_values_ptr = (uintptr_t)r->vals;
	return ioctl(fd, DRM_IOCTL_MODE_ATOMIC, &a) ? -errno : 0;
}

static uint32_t mode_blob(const struct drm_mode_modeinfo *m)
{
	struct drm_mode_create_blob b;

	memset(&b, 0, sizeof(b));
	b.data = (uintptr_t)m;
	b.length = sizeof(*m);
	if (xioctl(DRM_IOCTL_MODE_CREATEPROPBLOB, &b)) {
		perror("CREATEPROPBLOB");
		exit(2);
	}
	return b.blob_id;
}

/* the whole pipe: mode (blob 0 for a flip), the primary plane over @fb, others off */
static int commit(struct pipe *pp, uint32_t blob, const struct fb *fb, uint32_t flags)
{
	struct req r;
	int i;

	memset(&r, 0, sizeof(r));
	if (blob) {
		req_add(&r, pp->conn.id, pp->p.conn_crtc, pp->crtc_id);
		req_add(&r, pp->crtc_id, pp->p.crtc_mode, blob);
		req_add(&r, pp->crtc_id, pp->p.crtc_active, 1);
		flags |= DRM_MODE_ATOMIC_ALLOW_MODESET;
	}
	req_add(&r, pp->plane_id, pp->p.fb, fb->id);
	req_add(&r, pp->plane_id, pp->p.crtc, pp->crtc_id);
	req_add(&r, pp->plane_id, pp->p.sx, 0);
	req_add(&r, pp->plane_id, pp->p.sy, 0);
	req_add(&r, pp->plane_id, pp->p.sw, (uint64_t)fb->width << 16);
	req_add(&r, pp->plane_id, pp->p.sh, (uint64_t)fb->height << 16);
	req_add(&r, pp->plane_id, pp->p.cx, 0);
	req_add(&r, pp->plane_id, pp->p.cy, 0);
	req_add(&r, pp->plane_id, pp->p.cw, fb->width);
	req_add(&r, pp->plane_id, pp->p.ch, fb->height);
	for (i = 0; blob && i < pp->count_other && r.nobj < 8; i++) {
		req_add(&r, pp->other_planes[i], pp->p.fb, 0);
		req_add(&r, pp->other_planes[i], pp->p.crtc, 0);
	}
	return req_commit(&r, flags);
}

static void setup_pipe(const char *name, struct pipe *pp)
{
	struct plane planes[MAX_IDS];
	int n, i;

	memset(pp, 0, sizeof(*pp));
	if (find_connector(name, &pp->conn)) {
		fprintf(stderr, "no connector %s\n", name);
		exit(2);
	}
	if (find_crtc(&pp->conn, &pp->crtc_id, &pp->crtc_index)) {
		fprintf(stderr, "no CRTC for %s\n", name);
		exit(2);
	}
	n = get_planes(planes);
	for (i = 0; i < n; i++) {
		if (!(planes[i].possible_crtcs & (1u << pp->crtc_index)))
			continue;
		if (planes[i].type == PLANE_TYPE_PRIMARY && !pp->plane_id &&
		    (!planes[i].crtc_id || planes[i].crtc_id == pp->crtc_id))
			pp->plane_id = planes[i].id;
		else if (planes[i].crtc_id == pp->crtc_id)
			pp->other_planes[pp->count_other++] = planes[i].id;
	}
	if (!pp->plane_id) {
		fprintf(stderr, "no primary plane for CRTC %u\n", pp->crtc_id);
		exit(2);
	}
	pp->p.conn_crtc = prop_id(pp->conn.id, DRM_MODE_OBJECT_CONNECTOR, "CRTC_ID");
	pp->p.crtc_mode = prop_id(pp->crtc_id, DRM_MODE_OBJECT_CRTC, "MODE_ID");
	pp->p.crtc_active = prop_id(pp->crtc_id, DRM_MODE_OBJECT_CRTC, "ACTIVE");
	pp->p.fb = prop_id(pp->plane_id, DRM_MODE_OBJECT_PLANE, "FB_ID");
	pp->p.crtc = prop_id(pp->plane_id, DRM_MODE_OBJECT_PLANE, "CRTC_ID");
	pp->p.sx = prop_id(pp->plane_id, DRM_MODE_OBJECT_PLANE, "SRC_X");
	pp->p.sy = prop_id(pp->plane_id, DRM_MODE_OBJECT_PLANE, "SRC_Y");
	pp->p.sw = prop_id(pp->plane_id, DRM_MODE_OBJECT_PLANE, "SRC_W");
	pp->p.sh = prop_id(pp->plane_id, DRM_MODE_OBJECT_PLANE, "SRC_H");
	pp->p.cx = prop_id(pp->plane_id, DRM_MODE_OBJECT_PLANE, "CRTC_X");
	pp->p.cy = prop_id(pp->plane_id, DRM_MODE_OBJECT_PLANE, "CRTC_Y");
	pp->p.cw = prop_id(pp->plane_id, DRM_MODE_OBJECT_PLANE, "CRTC_W");
	pp->p.ch = prop_id(pp->plane_id, DRM_MODE_OBJECT_PLANE, "CRTC_H");
	printf("connector %s (%u), CRTC %u (index %d), primary plane %u, %d other planes on the CRTC\n",
	       pp->conn.name, pp->conn.id, pp->crtc_id, pp->crtc_index, pp->plane_id,
	       pp->count_other);
}

/* --- CRC ----------------------------------------------------------------- */

struct crc {
	uint32_t frame, value;
};

static void debugfs_path(char *buf, size_t len, int crtc_index, const char *file)
{
	snprintf(buf, len, "/sys/kernel/debug/dri/%d/crtc-%d/crc/%s", card, crtc_index, file);
}

static int crc_start(int crtc_index)
{
	char path[128];
	int cfd, dfd;

	debugfs_path(path, sizeof(path), crtc_index, "control");
	cfd = open(path, O_WRONLY);
	if (cfd < 0 || write(cfd, "auto", 4) != 4) {
		perror(path);
		exit(2);
	}
	close(cfd);
	debugfs_path(path, sizeof(path), crtc_index, "data");
	dfd = open(path, O_RDONLY | O_NONBLOCK);
	if (dfd < 0) {
		perror(path);
		exit(2);
	}
	return dfd;
}

/* the entries captured so far; the first value of each line */
static int crc_read(int dfd, struct crc *out, int max)
{
	static char buf[CRC_MAX * 64 + 1];
	static size_t used;
	int n = 0;
	ssize_t got;
	char *line, *nl;

	for (;;) {
		got = read(dfd, buf + used, sizeof(buf) - 1 - used);
		if (got <= 0) {
			if (got < 0 && errno != EAGAIN)
				perror("CRC read");
			break;
		}
		used += got;
		if (used >= sizeof(buf) - 1)
			break;
	}
	/* each entry is LINE_LEN bytes, its newline followed by a NUL */
	for (size_t k = 0; k < used; k++)
		if (!buf[k])
			buf[k] = ' ';
	buf[used] = 0;
	line = buf;
	while (n < max && (nl = strchr(line, '\n'))) {
		unsigned int frame, value;

		*nl = 0;
		/* "0x%08x" frame (drm_debugfs_crc.c), or XXXXXXXXXX without a frame counter */
		if (sscanf(line, "%x %x", &frame, &value) == 2) {
			out[n].frame = frame;
			out[n].value = value;
			n++;
		}
		line = nl + 1;
	}
	used = strlen(line);
	memmove(buf, line, used);
	return n;
}

static void sleep_frames(const struct drm_mode_modeinfo *m, unsigned int frames)
{
	unsigned int hz = mode_hz(m) ? mode_hz(m) : 60;
	struct timespec ts = {
		.tv_sec = frames / hz,
		.tv_nsec = (long)(frames % hz) * (1000000000L / hz),
	};

	nanosleep(&ts, NULL);
}

/* the CRC most frames of a still picture have, after the first few */
static uint32_t still_crc(struct crc *c, int n)
{
	int i, j, best = -1, best_count = 0;

	for (i = 2; i < n; i++) {
		int count = 0;

		for (j = 2; j < n; j++)
			count += c[j].value == c[i].value;
		if (count > best_count) {
			best_count = count;
			best = i;
		}
	}
	if (best < 0)
		return 0;
	printf("  %d of %d frames with CRC 0x%08x\n", best_count, n - 2, c[best].value);
	return c[best].value;
}

static uint32_t reference(struct pipe *pp, const struct drm_mode_modeinfo *mode2d,
			  uint32_t blob2d, uint32_t colour)
{
	struct crc c[CRC_MAX];
	struct fb fb;
	int dfd, n, ret;

	make_fb(&fb, mode2d->hdisplay, mode2d->vdisplay, colour, colour);
	ret = commit(pp, blob2d, &fb, 0);
	if (ret) {
		fprintf(stderr, "2D commit failed: %s\n", strerror(-ret));
		exit(1);
	}
	sleep_frames(mode2d, 4);
	dfd = crc_start(pp->crtc_index);
	sleep_frames(mode2d, 24);
	n = crc_read(dfd, c, CRC_MAX);
	close(dfd);
	printf("reference 0x%06x: %d frames\n", colour, n);
	if (getenv("FS_PROBE_DEBUG"))
		for (int k = 0; k < n; k++)
			printf("  frame %u crc 0x%08x\n", c[k].frame, c[k].value);
	return still_crc(c, n);
}

static int eye_of(uint32_t value, const uint32_t *refs, int nrefs)
{
	int i;

	for (i = 0; i < nrefs; i++)
		if (value == refs[i])
			return i;
	return -1;
}

static void print_stereo_state(const struct pipe *pp)
{
	char path[160], line[256];
	FILE *f;

	snprintf(path, sizeof(path), "/sys/kernel/debug/dri/%d/%s/stereo_state", card, pp->conn.name);
	f = fopen(path, "r");
	if (!f) {
		printf("%s: %s\n", path, strerror(errno));
		return;
	}
	while (fgets(line, sizeof(line), f))
		printf("  %s", line);
	fclose(f);
}

/* --- commands ------------------------------------------------------------ */

static int cmd_list(void)
{
	uint32_t i, j;

	for (i = 0; i < res.count_connectors; i++) {
		struct connector c;

		get_connector(connector_ids[i], &c);
		printf("%s (%u): %s, %u modes\n", c.name, c.id,
		       c.connection == 1 ? "connected" : c.connection == 2 ? "disconnected" : "unknown",
		       c.count_modes);
		for (j = 0; j < c.count_modes; j++)
			if (c.modes[j].flags & DRM_MODE_FLAG_3D_MASK)
				print_mode("  ", &c.modes[j]);
		free(c.modes);
	}
	return 0;
}

static int cmd_test(const char *name)
{
	struct drm_mode_modeinfo mode2d, modefs;
	struct pipe pp;
	struct fb fb;
	int ret2d, retfs;

	setup_pipe(name, &pp);
	pick_modes(&pp.conn, &mode2d, &modefs);
	print_mode("2D:", &mode2d);
	print_mode("frame sequential:", &modefs);
	make_fb(&fb, 2 * modefs.hdisplay, modefs.vdisplay, 0xff0000, 0x0000ff);
	retfs = commit(&pp, mode_blob(&modefs), &fb, DRM_MODE_ATOMIC_TEST_ONLY);
	printf("TEST_ONLY frame sequential, %ux%u linear frame: %s\n", fb.width, fb.height,
	       retfs ? strerror(-retfs) : "accepted");
	make_fb(&fb, mode2d.hdisplay, mode2d.vdisplay, 0xff0000, 0xff0000);
	ret2d = commit(&pp, mode_blob(&mode2d), &fb, DRM_MODE_ATOMIC_TEST_ONLY);
	printf("TEST_ONLY 2D, %ux%u frame (control): %s\n", fb.width, fb.height,
	       ret2d ? strerror(-ret2d) : "accepted");
	return retfs ? 1 : 0;
}

static int cmd_run(const char *name)
{
	const uint32_t colours[4] = { 0xff0000, 0x0000ff, 0x00ff00, 0xffff00 };
	static const char *const colour_names[4] = { "red", "blue", "green", "yellow" };
	struct drm_mode_modeinfo mode2d, modefs;
	struct crc c[CRC_MAX];
	uint32_t refs[4], blob2d, blobfs;
	struct fb a, b;
	struct pipe pp;
	int dfd, n, i, ret, unknown = 0, repeats = 0, gaps = 0, counted[4] = { 0 };
	int pairs = 0, mixed = 0, flips;
	bool fail = false;

	setup_pipe(name, &pp);
	pick_modes(&pp.conn, &mode2d, &modefs);
	print_mode("2D:", &mode2d);
	print_mode("frame sequential:", &modefs);
	blob2d = mode_blob(&mode2d);
	blobfs = mode_blob(&modefs);

	/* 1. a CRC for each colour, in 2D */
	for (i = 0; i < 4; i++) {
		refs[i] = reference(&pp, &mode2d, blob2d, colours[i]);
		printf("  = %s\n", colour_names[i]);
	}
	for (i = 1; i < 4; i++)
		if (refs[i] == refs[0] || (i > 1 && refs[i] == refs[1]) || (i > 2 && refs[i] == refs[2])) {
			fprintf(stderr, "two colours share a CRC; cannot tell the eyes apart\n");
			return 1;
		}

	/* 2. alternation: left red, right blue */
	make_fb(&a, 2 * modefs.hdisplay, modefs.vdisplay, colours[0], colours[1]);
	make_fb(&b, 2 * modefs.hdisplay, modefs.vdisplay, colours[2], colours[3]);
	ret = commit(&pp, blobfs, &a, 0);
	if (ret) {
		fprintf(stderr, "frame-sequential commit refused: %s\n", strerror(-ret));
		return 1;
	}
	sleep_frames(&modefs, 4);
	printf("stereo_state after the frame-sequential commit, read 6 times:\n");
	for (i = 0; i < 6; i++) {
		print_stereo_state(&pp);
		printf("  --\n");
		sleep_frames(&modefs, 1);
	}
	dfd = crc_start(pp.crtc_index);
	sleep_frames(&modefs, 100);
	n = crc_read(dfd, c, CRC_MAX);
	close(dfd);
	printf("alternation: %d frames\n", n);
	for (i = 0; i < n; i++) {
		int eye = eye_of(c[i].value, refs, 4);

		if (eye < 0 || eye > 1)
			unknown++;
		else
			counted[eye]++;
		if (i && c[i].frame != c[i - 1].frame + 1)
			gaps++;
		else if (i && c[i].value == c[i - 1].value)
			repeats++;
		if (i < 16)
			printf("  frame %u crc 0x%08x %s\n", c[i].frame, c[i].value,
			       eye == 0 ? "left (red)" : eye == 1 ? "right (blue)" : "neither eye");
	}
	printf("alternation: %d left, %d right, %d neither, %d same-eye repeats, %d frame gaps\n",
	       counted[0], counted[1], unknown, repeats, gaps);
	if (n < 32 || unknown || repeats || abs(counted[0] - counted[1]) > 1 + gaps) {
		printf("alternation: FAIL\n");
		fail = true;
	} else {
		printf("alternation: PASS\n");
	}

	/* 3. flips: a (red|blue) and b (green|yellow), one after the other */
	dfd = crc_start(pp.crtc_index);
	for (flips = 0; flips < 40; flips++) {
		ret = commit(&pp, 0, flips % 2 ? &a : &b, 0);
		if (ret) {
			fprintf(stderr, "flip %d failed: %s\n", flips, strerror(-ret));
			fail = true;
			break;
		}
	}
	sleep_frames(&modefs, 4);
	n = crc_read(dfd, c, CRC_MAX);
	close(dfd);
	unknown = 0;
	for (i = 0; i + 1 < n; i++) {
		int eye = eye_of(c[i].value, refs, 4), next = eye_of(c[i + 1].value, refs, 4);

		if (eye < 0)
			unknown++;
		if (c[i + 1].frame != c[i].frame + 1)
			continue;
		/* a left-eye frame (red or green) and the frame after it */
		if (eye == 0 || eye == 2) {
			pairs++;
			if (next != eye + 1) {
				mixed++;
				printf("  frames %u, %u: %s then %s\n", c[i].frame, c[i + 1].frame,
				       colour_names[eye], next < 0 ? "neither" : colour_names[next]);
			}
		}
	}
	printf("flips: %d flips, %d frames, %d pairs, %d pairs from two framebuffers, %d frames of no colour\n",
	       flips, n, pairs, mixed, unknown);
	if (pairs < 8 || mixed || unknown) {
		printf("flips: FAIL\n");
		fail = true;
	} else {
		printf("flips: PASS\n");
	}

	printf("stereo_state at the end:\n");
	print_stereo_state(&pp);
	return fail ? 1 : 0;
}

int main(int argc, char **argv)
{
	char path[64];

	if (argc < 3 || (strcmp(argv[1], "list") && argc < 4)) {
		fprintf(stderr, "usage: %s list CARD | test CARD CONNECTOR | run CARD CONNECTOR\n",
			argv[0]);
		return 2;
	}
	card = atoi(argv[2]);
	snprintf(path, sizeof(path), "/dev/dri/card%d", card);
	fd = open(path, O_RDWR | O_CLOEXEC);
	if (fd < 0) {
		perror(path);
		return 2;
	}
	{
		struct drm_set_client_cap cap = { .capability = DRM_CLIENT_CAP_STEREO_3D, .value = 1 };

		if (xioctl(DRM_IOCTL_SET_CLIENT_CAP, &cap))
			perror("STEREO_3D");
		cap.capability = DRM_CLIENT_CAP_UNIVERSAL_PLANES;
		if (xioctl(DRM_IOCTL_SET_CLIENT_CAP, &cap))
			perror("UNIVERSAL_PLANES");
		cap.capability = DRM_CLIENT_CAP_ATOMIC;
		if (xioctl(DRM_IOCTL_SET_CLIENT_CAP, &cap)) {
			perror("ATOMIC");
			return 2;
		}
	}
	get_resources();

	if (!strcmp(argv[1], "list"))
		return cmd_list();
	if (!strcmp(argv[1], "test"))
		return cmd_test(argv[3]);
	if (!strcmp(argv[1], "run"))
		return cmd_run(argv[3]);
	fprintf(stderr, "unknown command %s\n", argv[1]);
	return 2;
}
