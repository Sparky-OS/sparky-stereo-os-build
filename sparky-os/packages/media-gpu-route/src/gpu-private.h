/* Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: MIT */
#ifndef MEDIA_GPU_PRIVATE_H
#define MEDIA_GPU_PRIVATE_H
#include "media-gpu-route.h"
int media_gpu_routes(struct media_gpu_route **out);
/* Moves the GPU the Graphics page names for players to the front, keeping the others in order. */
void media_gpu_route_prefer_graphics_page(struct media_gpu_route *routes, int count);
int media_gpu_vaapi_supports(const struct media_gpu_video *, const struct media_gpu_route *);
int media_gpu_cuda_supports(const struct media_gpu_video *, const struct media_gpu_route *, char device[128]);
int media_gpu_read_bool(const char *path, const char *group, const char *key, int *value);
#endif
