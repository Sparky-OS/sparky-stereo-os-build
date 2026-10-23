/* Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: MIT */
#ifndef MEDIA_GPU_PRIVATE_H
#define MEDIA_GPU_PRIVATE_H
#include "media-gpu-route.h"
int media_gpu_routes(struct media_gpu_route **out);
int media_gpu_vaapi_supports(const struct media_gpu_video *, const struct media_gpu_route *);
int media_gpu_cuda_supports(const struct media_gpu_video *, const struct media_gpu_route *, char device[128]);
#endif
