/*
 * nvkms-query: report what NVIDIA's NVKMS chose for each connected display
 * (colour depth, format, range). Read-only: it allocates an NVKMS device
 * handle, queries, and frees it. It never sets an attribute or a mode.
 *
 * Uses the interface of NVIDIA's open GPU kernel modules (MIT licensed
 * headers: src/nvidia-modeset/interface/nvkms-*.h).
 * This file: MIT.
 */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include "nvkms-api.h"
#include "nvkms-ioctl.h"

#ifndef NVKMS_DRIVER_VERSION
#define NVKMS_DRIVER_VERSION "615.71.09"
#endif

static int fd = -1, quiet;

static int call(enum NvKmsIoctlCommand cmd, void *p, size_t size, const char *what)
{
	struct NvKmsIoctlParams ip;

	memset(&ip, 0, sizeof ip);
	ip.cmd = cmd;
	ip.size = (NvU32)size;
	ip.address = nvKmsPointerToNvU64(p);
	if (ioctl(fd, NVKMS_IOCTL_IOWR, &ip) < 0) {
		if (quiet)
			return -1;
		fprintf(stderr, "nvkms-query: %s failed: errno=%d (%s); "
			"cmd=%u params size=%zu sizeof(NvKmsIoctlParams)=%zu\n",
			what, errno, strerror(errno), (unsigned)cmd, size, sizeof ip);
		return -1;
	}
	return 0;
}

static int getattr(NvKmsDeviceHandle dev, NvKmsDispHandle disp, NVDpyId id,
		   enum NvKmsDpyAttribute a, long long *v)
{
	struct NvKmsGetDpyAttributeParams p;

	memset(&p, 0, sizeof p);
	p.request.deviceHandle = dev;
	p.request.dispHandle = disp;
	p.request.dpyId = id;
	p.request.attribute = a;
	if (ioctl(fd, NVKMS_IOCTL_IOWR, &(struct NvKmsIoctlParams){
		.cmd = NVKMS_IOCTL_GET_DPY_ATTRIBUTE, .size = sizeof p,
		.address = nvKmsPointerToNvU64(&p) }) < 0)
		return -1;
	*v = p.reply.value;
	return 0;
}

static void validvalues(NvKmsDeviceHandle dev, NvKmsDispHandle disp, NVDpyId id,
			enum NvKmsDpyAttribute a, char *out, size_t n)
{
	struct NvKmsGetDpyAttributeValidValuesParams p;
	struct NvKmsAttributeValidValuesCommonReply *c = &p.reply.common;

	out[0] = 0;
	memset(&p, 0, sizeof p);
	p.request.deviceHandle = dev;
	p.request.dispHandle = disp;
	p.request.dpyId = id;
	p.request.attribute = a;
	if (ioctl(fd, NVKMS_IOCTL_IOWR, &(struct NvKmsIoctlParams){
		.cmd = NVKMS_IOCTL_GET_DPY_ATTRIBUTE_VALID_VALUES, .size = sizeof p,
		.address = nvKmsPointerToNvU64(&p) }) < 0)
		return;
	if (c->type == NV_KMS_ATTRIBUTE_TYPE_INTBITS) {
		size_t l = 0;
		for (int b = 0; b < 32; b++)
			if ((c->u.bits.ints >> b) & 1)
				l += snprintf(out + l, n - l, "%s%d", l ? "," : "", b);
	} else if (c->type == NV_KMS_ATTRIBUTE_TYPE_RANGE) {
		snprintf(out, n, "%lld-%lld", (long long)c->u.range.min,
			 (long long)c->u.range.max);
	} else if (c->type == NV_KMS_ATTRIBUTE_TYPE_BITMASK) {
		snprintf(out, n, "mask:0x%x", c->u.bits.ints);
	}
}

static const char *fmt_name(long long v)
{
	switch (v) {
	case 0: return "rgb";
	case 1: return "ycbcr422";
	case 2: return "ycbcr444";
	case 3: return "ycbcr420";
	}
	return "unknown";
}

static const char *range_name(long long v)
{
	return v == 0 ? "full" : v == 1 ? "limited" : "unknown";
}

static int query_gpu(NvU32 rmid)
{
	struct NvKmsAllocDeviceParams *ap = calloc(1, sizeof *ap);
	struct NvKmsFreeDeviceParams fp;
	NvKmsDeviceHandle dev;
	int shown = 0;

	strncpy(ap->request.versionString, NVKMS_DRIVER_VERSION,
		sizeof ap->request.versionString - 1);
	ap->request.deviceId.rmDeviceId = rmid;
	ap->request.deviceId.migDevice = NO_MIG_DEVICE;
	ap->request.no3d = NV_TRUE;
	/* TRUE: do not let our open/close change console hotplug behaviour */
	ap->request.enableConsoleHotplugHandling = NV_TRUE;

	/* NVKMS refuses unknown GPU instances with EPERM: end of the GPU list */
	quiet = rmid > 0;
	if (call(NVKMS_IOCTL_ALLOC_DEVICE, ap, sizeof *ap, "ALLOC_DEVICE")) {
		quiet = 0;
		if (rmid > 0) { free(ap); return 1; }
		fprintf(stderr, "  sizeof(NvKmsAllocDeviceParams)=%zu\n", sizeof *ap);
		free(ap);
		return -1;
	}
	quiet = 0;
	if (ap->reply.status != NVKMS_ALLOC_DEVICE_STATUS_SUCCESS) {
		if (ap->reply.status == NVKMS_ALLOC_DEVICE_STATUS_NO_HARDWARE_AVAILABLE) {
			free(ap);
			return 1; /* no such GPU instance */
		}
		fprintf(stderr, "nvkms-query: ALLOC_DEVICE gpu %u status=%d "
			"(1=version mismatch, 2=bad request)\n", rmid, ap->reply.status);
		free(ap);
		return -1;
	}
	dev = ap->reply.deviceHandle;

	for (NvU32 d = 0; d < ap->reply.numDisps; d++) {
		NvKmsDispHandle disp = ap->reply.dispHandles[d];
		struct NvKmsQueryDispParams qd;

		memset(&qd, 0, sizeof qd);
		qd.request.deviceHandle = dev;
		qd.request.dispHandle = disp;
		if (call(NVKMS_IOCTL_QUERY_DISP, &qd, sizeof qd, "QUERY_DISP"))
			continue;

		NVDpyId id;
		FOR_ALL_DPY_IDS(id, qd.reply.validDpys) {
			struct NvKmsQueryDpyDynamicDataParams *dd;
			struct NvKmsQueryDpyStaticDataParams sd;
			long long bpc = 0, f = 3, r = 3;
			char valid[128], name[NVKMS_DPY_NAME_SIZE];

			dd = calloc(1, sizeof *dd);
			dd->request.deviceHandle = dev;
			dd->request.dispHandle = disp;
			dd->request.dpyId = id;
			/* all force/override flags stay FALSE: pure query */
			if (call(NVKMS_IOCTL_QUERY_DPY_DYNAMIC_DATA, dd, sizeof *dd,
				 "QUERY_DPY_DYNAMIC_DATA")) {
				fprintf(stderr, "  sizeof(NvKmsQueryDpyDynamicDataParams)=%zu\n",
					sizeof *dd);
				free(dd);
				continue;
			}
			snprintf(name, sizeof name, "%s", dd->reply.name);
			if (!dd->reply.connected) { free(dd); continue; }

			memset(&sd, 0, sizeof sd);
			sd.request.deviceHandle = dev;
			sd.request.dispHandle = disp;
			sd.request.dpyId = id;
			call(NVKMS_IOCTL_QUERY_DPY_STATIC_DATA, &sd, sizeof sd,
			     "QUERY_DPY_STATIC_DATA");

			getattr(dev, disp, id, NV_KMS_DPY_ATTRIBUTE_CURRENT_COLOR_BPC, &bpc);
			getattr(dev, disp, id, NV_KMS_DPY_ATTRIBUTE_CURRENT_COLOR_FORMAT, &f);
			getattr(dev, disp, id, NV_KMS_DPY_ATTRIBUTE_CURRENT_COLOR_RANGE, &r);
			validvalues(dev, disp, id, NV_KMS_DPY_ATTRIBUTE_CURRENT_COLOR_BPC,
				    valid, sizeof valid);

			printf("%s connected bpc=%lld format=%s range=%s", name, bpc,
			       fmt_name(f), range_name(r));
			if (valid[0])
				printf(" valid_bpc=%s", valid);
			printf("\n");
			shown++;
			free(dd);
		}
	}

	memset(&fp, 0, sizeof fp);
	fp.request.deviceHandle = dev;
	call(NVKMS_IOCTL_FREE_DEVICE, &fp, sizeof fp, "FREE_DEVICE");
	free(ap);
	return shown ? 0 : 2;
}

int main(void)
{
	int any = 0, rc = 0;

	fd = open("/dev/nvidia-modeset", O_RDWR);
	if (fd < 0) {
		fprintf(stderr, "nvkms-query: open /dev/nvidia-modeset: %s\n",
			strerror(errno));
		return 1;
	}
	/* rmDeviceId is the RM device instance (0 = first GPU); this is what
	 * nvidia-drm passes (nvkms-kapi.c: deviceId.rmDeviceId = deviceInstance). */
	for (NvU32 g = 0; g < 8; g++) {
		int r = query_gpu(g);
		if (r == 1) break;
		if (r < 0) rc = 1;
		any = 1;
	}
	if (!any) { fprintf(stderr, "nvkms-query: no GPU found\n"); rc = 1; }
	close(fd);
	return rc;
}
