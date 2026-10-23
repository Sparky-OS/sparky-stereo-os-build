/* Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: MIT */
#ifndef MEDIA_GPU_ROUTE_H
#define MEDIA_GPU_ROUTE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
struct media_gpu_route {
    uint32_t vendor_id;
    uint32_t device_id;
    uint64_t drm_device;
    char render_node[128];
    char name[256];
};
/* Resolve the loader's display preference, including explicit driver overrides.
 * No logical GPU device is created and no user configuration is written.
 * Return 1 on success, 0 when no suitable hardware device is discoverable. */
int media_gpu_route_default(struct media_gpu_route *route);
enum media_gpu_codec {
    MEDIA_GPU_CODEC_UNKNOWN, MEDIA_GPU_CODEC_H264, MEDIA_GPU_CODEC_HEVC,
    MEDIA_GPU_CODEC_VP8, MEDIA_GPU_CODEC_VP9, MEDIA_GPU_CODEC_AV1,
    MEDIA_GPU_CODEC_MPEG1, MEDIA_GPU_CODEC_MPEG2, MEDIA_GPU_CODEC_MPEG4,
    MEDIA_GPU_CODEC_VC1, MEDIA_GPU_CODEC_MJPEG
};
enum media_gpu_backend { MEDIA_GPU_SOFTWARE, MEDIA_GPU_VAAPI, MEDIA_GPU_CUDA };
struct media_gpu_video {
    enum media_gpu_codec codec;
    int profile;
    int bits;
    int components;
    int log2_chroma_w;
    int log2_chroma_h;
    int rgb;
    int width;
    int height;
};
struct media_gpu_decoder {
    struct media_gpu_route gpu;
    enum media_gpu_backend backend;
    char device[128];
};
/* Prefer the display GPU when it can decode the supplied profile without
 * losing components, chroma or bits, otherwise try the next hardware GPU.
 * Return 1 for a driver-supported choice, 0 for software, -1 if capability
 * information is unavailable. Unknown never means supported. */
int media_gpu_route_decoder(const struct media_gpu_video *video, struct media_gpu_decoder *decoder);
#ifdef __cplusplus
}
#endif
#endif
