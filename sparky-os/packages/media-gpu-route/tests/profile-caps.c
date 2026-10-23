/* Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: MIT */
#include "gpu-private.h"
#include <stdio.h>
int main(void)
{
    struct media_gpu_route gpu = {0};
    struct media_gpu_video video = { .codec = MEDIA_GPU_CODEC_VC1, .profile = 2,
        .bits = 8, .components = 3, .log2_chroma_w = 1, .log2_chroma_h = 1,
        .width = 640, .height = 192 };
    /* VC-1 Complex is 2; Advanced is 3. An empty node cannot open a device. */
    int complex = media_gpu_vaapi_supports(&video, &gpu);
    char selector[128];
    int cuda_complex = media_gpu_cuda_supports(&video, &gpu, selector);
    video.profile = 3;
    int advanced = media_gpu_vaapi_supports(&video, &gpu);
    printf("Complex VAAPI=%d CUDA=%d (unknown), Advanced VAAPI=%d (no device)\n",
           complex, cuda_complex, advanced);
    return complex != -1 || cuda_complex != -1 || advanced != 0;
}
