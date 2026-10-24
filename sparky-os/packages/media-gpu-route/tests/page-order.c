/* Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: MIT */
#include "gpu-private.h"
#include <stdio.h>
#include <string.h>
/* page-order NODE...: the order media_gpu_route_prefer_graphics_page gives these render nodes. */
int main(int argc, char **argv)
{
    struct media_gpu_route routes[8];
    int count = argc - 1 < 8 ? argc - 1 : 8;
    memset(routes, 0, sizeof(routes));
    for (int i = 0; i < count; i++)
        snprintf(routes[i].render_node, sizeof(routes[i].render_node), "%s", argv[i + 1]);
    media_gpu_route_prefer_graphics_page(routes, count);
    for (int i = 0; i < count; i++)
        printf("%s%s", i ? " " : "", routes[i].render_node);
    printf("\n");
    return 0;
}
