/* Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: MIT */
#include "media-gpu-route.h"
#include <stdio.h>
int main(void)
{
    struct media_gpu_route route;
    if (!media_gpu_route_default(&route))
        return 1;
    printf("vendor=%04x device=%04x node=%s name=%s\n", route.vendor_id, route.device_id, route.render_node, route.name);
    return 0;
}
