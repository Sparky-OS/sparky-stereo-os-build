/* Test control only: choose the render device of an isolated virtual KWin.
 * Client processes must not preload this module.
 * Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: MIT */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <xf86drm.h>
int drmGetDevices2(uint32_t flags, drmDevicePtr devices[], int max_devices)
{
    int (*original)(uint32_t, drmDevicePtr[], int) = dlsym(RTLD_NEXT, "drmGetDevices2");
    if (!original) { errno = ENOSYS; return -1; }
    int count = original(flags, devices, max_devices);
    const char *wanted = getenv("RIG_COMPOSITOR_RENDER_NODE");
    if (!devices || !wanted || count < 2)
        return count;
    for (int i = 1; i < count; i++) {
        if ((devices[i]->available_nodes & (1 << DRM_NODE_RENDER))
            && !strcmp(devices[i]->nodes[DRM_NODE_RENDER], wanted)) {
            drmDevicePtr preferred = devices[i];
            memmove(devices + 1, devices, i * sizeof(*devices));
            devices[0] = preferred;
            break;
        }
    }
    return count;
}
