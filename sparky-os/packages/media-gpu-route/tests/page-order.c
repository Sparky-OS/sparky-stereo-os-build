/* Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: MIT */
#include "gpu-private.h"
#include <stdio.h>
#include <string.h>
/* page-order NODE...: the order media_gpu_route_prefer_graphics_page gives these render nodes, and what the page
 * answered (named, not-asked, failed STATUS, not-found NODE). */
int main(int argc, char **argv)
{
    struct media_gpu_route routes[8];
    int count = argc - 1 < 8 ? argc - 1 : 8;
    memset(routes, 0, sizeof(routes));
    for (int i = 0; i < count; i++)
        snprintf(routes[i].render_node, sizeof(routes[i].render_node), "%s", argv[i + 1]);
    char node[128];
    int status;
    enum media_gpu_page page = media_gpu_route_prefer_graphics_page(routes, count, node, &status);
    for (int i = 0; i < count; i++)
        printf("%s%s", i ? " " : "", routes[i].render_node);
    if (page == MEDIA_GPU_PAGE_NAMED)
        printf(" | named\n");
    else if (page == MEDIA_GPU_PAGE_NOT_ASKED)
        printf(" | not-asked\n");
    else if (page == MEDIA_GPU_PAGE_FAILED)
        printf(" | failed %d\n", status);
    else
        printf(" | not-found %s\n", node);
    return 0;
}
