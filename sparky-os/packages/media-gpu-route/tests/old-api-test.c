/* Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: MIT */
/* Through the 0.2 entry point only, as MLT and VLC call it, so the same test runs against 0.2.1: prints its result. */
#include "media-gpu-route.h"
#include <stdio.h>

int main(void)
{
    struct media_gpu_video video = { .codec = MEDIA_GPU_CODEC_H264, .profile = 100, .bits = 8,
        .components = 3, .log2_chroma_w = 1, .log2_chroma_h = 1, .width = 1920, .height = 1080 };
    struct media_gpu_decoder decoder;
    printf("result=%d\n", media_gpu_route_decoder(&video, &decoder));
    return 0;
}
