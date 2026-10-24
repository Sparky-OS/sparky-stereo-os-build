/* Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: MIT */
#include "gpu-private.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *const codecs[] = {
    [MEDIA_GPU_CODEC_H264] = "h264", [MEDIA_GPU_CODEC_HEVC] = "hevc", [MEDIA_GPU_CODEC_VP8] = "vp8",
    [MEDIA_GPU_CODEC_VP9] = "vp9", [MEDIA_GPU_CODEC_AV1] = "av1", [MEDIA_GPU_CODEC_MPEG1] = "mpeg1",
    [MEDIA_GPU_CODEC_MPEG2] = "mpeg2", [MEDIA_GPU_CODEC_MPEG4] = "mpeg4", [MEDIA_GPU_CODEC_VC1] = "vc1",
    [MEDIA_GPU_CODEC_MJPEG] = "mjpeg",
};

static int usage(void)
{
    fprintf(stderr, "usage: media-gpu-route-query [--capabilities | --decoder CODEC PROFILE BITS WIDTHxHEIGHT copy|import]\n");
    return 2;
}

static int capabilities(void)
{
    struct media_gpu_route *routes = NULL;
    int count = media_gpu_routes(&routes);
    for (int i = 0; i < count; i++) {
        int import = media_gpu_route_vulkan_import(&routes[i]);
        printf("gpu=%d vendor=%04x device=%04x node=%s vulkan-import=%s name=%s\n", i, routes[i].vendor_id,
               routes[i].device_id, routes[i].render_node, import > 0 ? "yes" : import ? "unknown" : "no",
               routes[i].name);
    }
    free(routes);
    printf("gpus=%d copy-back=%s\n", count, media_gpu_route_copy_back() ? "allowed" : "not-allowed");
    return 0;
}

static int decoder(char **argv)
{
    struct media_gpu_video video = { .components = 3, .log2_chroma_w = 1, .log2_chroma_h = 1 };
    for (size_t i = 1; i < sizeof(codecs) / sizeof(codecs[0]); i++)
        if (!strcmp(argv[0], codecs[i]))
            video.codec = (enum media_gpu_codec)i;
    video.profile = atoi(argv[1]);
    video.bits = atoi(argv[2]);
    if (sscanf(argv[3], "%dx%d", &video.width, &video.height) != 2)
        return usage();
    enum media_gpu_frames frames;
    if (!strcmp(argv[4], "copy"))
        frames = MEDIA_GPU_FRAMES_COPY;
    else if (!strcmp(argv[4], "import"))
        frames = MEDIA_GPU_FRAMES_IMPORT;
    else
        return usage();
    struct media_gpu_decoder choice;
    int result = media_gpu_route_decoder_frames(&video, frames, &choice);
    if (result > 0)
        printf("result=hardware backend=%s device=%s gpu=%s\n", choice.backend == MEDIA_GPU_CUDA ? "cuda" : "vaapi",
               choice.device, choice.gpu.name);
    else
        printf("result=%s\n", result ? "unknown" : "software");
    return 0;
}

int main(int argc, char **argv)
{
    if (argc == 2 && !strcmp(argv[1], "--capabilities"))
        return capabilities();
    if (argc == 7 && !strcmp(argv[1], "--decoder"))
        return decoder(argv + 2);
    if (argc != 1)
        return usage();
    struct media_gpu_route route;
    if (!media_gpu_route_default(&route))
        return 1;
    printf("vendor=%04x device=%04x node=%s name=%s\n", route.vendor_id, route.device_id, route.render_node, route.name);
    return 0;
}
