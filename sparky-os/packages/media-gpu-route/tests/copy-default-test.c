/* Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: MIT */
/* Through the original entry point only, so the same test runs against 0.1.0:
 * a caller that copies its pictures back keeps software by default. */
#include "media-gpu-route.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void)
{
    setenv("XDG_CONFIG_DIRS", "/nonexistent", 1);
    setenv("XDG_CONFIG_HOME", "/nonexistent", 1);
    unsetenv("MEDIA_GPU_ROUTE_COPY_BACK");
    struct media_gpu_video video = { .codec = MEDIA_GPU_CODEC_H264, .profile = 100, .bits = 8,
        .components = 3, .log2_chroma_w = 1, .log2_chroma_h = 1, .width = 1920, .height = 1080 };
    struct media_gpu_decoder decoder;
    int result = media_gpu_route_decoder(&video, &decoder);
    printf("H.264 High 1080p, copy-back caller, nothing allowed: result=%d (%s) %s\n", result,
           result > 0 ? decoder.device : result ? "unknown" : "software", result == 0 ? "ok" : "FAIL");
    return result != 0;
}
