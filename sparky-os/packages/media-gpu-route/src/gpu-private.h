/* Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: MIT */
#ifndef MEDIA_GPU_PRIVATE_H
#define MEDIA_GPU_PRIVATE_H
#include "media-gpu-route.h"
int media_gpu_routes(struct media_gpu_route **out);
/* What the Graphics page answered for players' GPU */
enum media_gpu_page {
    MEDIA_GPU_PAGE_NOT_ASKED, /* a GPU chosen at launch, the page not installed, or one GPU: the graphics stack's order */
    MEDIA_GPU_PAGE_NAMED, /* routes[0] is the GPU it names */
    MEDIA_GPU_PAGE_FAILED, /* its command failed or answered nothing: *status is its exit status */
    MEDIA_GPU_PAGE_NOT_FOUND, /* it names a GPU that is not among the routes: node holds it */
};
/* Asks the Graphics page which GPU players use and moves that GPU to the front, keeping the others in order. */
enum media_gpu_page media_gpu_route_prefer_graphics_page(struct media_gpu_route *routes, int count, char node[128], int *status);
/* The person's language among the nine (LANGUAGE, LC_ALL, LC_MESSAGES, LANG; the whole name, then the bare
 * language, then English; Chinese keeps its territory). */
const char *media_gpu_route_language(void);
enum media_gpu_text { MEDIA_GPU_TEXT_PAGE_FAILED, MEDIA_GPU_TEXT_NOT_FOUND, MEDIA_GPU_TEXT_CANNOT_DECODE, MEDIA_GPU_TEXT_OTHER_GPU, MEDIA_GPU_TEXT_UNKNOWN,
                      MEDIA_GPU_TEXT_COPY_BACK_OFF };
/* The message in the person's language, a printf format with one argument (%d or %s as each says) */
const char *media_gpu_route_text(enum media_gpu_text text);
int media_gpu_vaapi_supports(const struct media_gpu_video *, const struct media_gpu_route *);
int media_gpu_cuda_supports(const struct media_gpu_video *, const struct media_gpu_route *, char device[128]);
int media_gpu_read_bool(const char *path, const char *group, const char *key, int *value);

#endif
