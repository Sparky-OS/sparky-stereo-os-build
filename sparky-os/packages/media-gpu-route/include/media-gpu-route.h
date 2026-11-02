/* Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: MIT */
#ifndef MEDIA_GPU_ROUTE_H
#define MEDIA_GPU_ROUTE_H
#include <stddef.h>
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
/* How the caller's decoded pictures reach the screen. */
enum media_gpu_frames {
    /* Every decoded picture is copied from the GPU back into system memory. */
    MEDIA_GPU_FRAMES_COPY,
    /* The renderer imports the decoder's surfaces directly, without a copy. */
    MEDIA_GPU_FRAMES_IMPORT,
};
/* Whether a hardware path that copies its pictures back may be taken without
 * the person choosing it. Copying back can be slower than software decoding
 * (an AMD A10-9600P drops many more frames that way), so it is never assumed.
 * It is allowed when MEDIA_GPU_ROUTE_COPY_BACK is true, else when CopyBack is
 * true in group [Decoding] of sparky-stereo-graphicsrc: the person's file in
 * $XDG_CONFIG_HOME over the machine's measured record in $XDG_CONFIG_DIRS
 * (/etc/xdg). Return 1 when allowed, 0 otherwise. Nothing is written. */
int media_gpu_route_copy_back(void);
/* Prefer the display GPU when it can decode the supplied profile without
 * losing components, chroma or bits, otherwise try the next hardware GPU.
 * A caller whose pictures are copied back gets software (0) unless
 * media_gpu_route_copy_back() allows it; a caller that imports them gets the
 * capability answer. Return 1 for a driver-supported choice, 0 for software,
 * -1 if capability information is unavailable. Unknown never means supported. */
int media_gpu_route_decoder_frames(const struct media_gpu_video *video, enum media_gpu_frames frames,
                                   struct media_gpu_decoder *decoder);
/* The choice for a caller that copies its pictures back:
 * media_gpu_route_decoder_frames(video, MEDIA_GPU_FRAMES_COPY, decoder). */
int media_gpu_route_decoder(const struct media_gpu_video *video, struct media_gpu_decoder *decoder);
/* 0.2.2. A caller that copies its pictures back decodes on the GPU the Graphics page names for players
 * (sparky-stereo-gpu-env), and on no other GPU unless the person allows it (media_gpu_route_other_gpu):
 * nothing changes GPU without telling (Daniel, 2026-11-01). As media_gpu_route_decoder_frames, and TEXT
 * (at most SIZE bytes, in the person's language; empty when there is nothing to say) says why the choice
 * is not that GPU's hardware decoder. Return -2 when the GPU chosen for players could not be resolved:
 * the Graphics page's command failed (it says why itself), answered nothing, or named a GPU this
 * program cannot open; nothing is decoded on another GPU in its place. The 0.2 entry points answer 0
 * (software) then, and write TEXT to stderr, so their callers use no other GPU either. */
int media_gpu_route_decoder_said(const struct media_gpu_video *video, enum media_gpu_frames frames,
                                 struct media_gpu_decoder *decoder, char *text, size_t size);
/* Whether a caller that copies its pictures back may decode on another GPU when the GPU the Graphics
 * page names for players cannot decode the video: MEDIA_GPU_ROUTE_OTHER_GPU, else OtherGpu in group
 * [Decoding] of sparky-stereo-graphicsrc (the person's file over the machine's), else not. Return 1
 * when allowed, 0 otherwise. Nothing is written. 0.2.2. */
int media_gpu_route_other_gpu(void);
/* What a caller says when it decodes in software because a conversion needs the decoded pictures in memory and
 * copying them back is not allowed (media_gpu_route_copy_back), in the person's language, with how to allow it.
 * A static string. 0.2.2. */
const char *media_gpu_route_copy_back_off_text(void);
/* Whether a Vulkan renderer on this GPU can import decoded surfaces without a
 * copy: dma-buf memory (VK_EXT_external_memory_dma_buf) laid out by DRM format
 * modifiers (VK_EXT_image_drm_format_modifier), which libplacebo requires.
 * Return 1 when the device offers both, 0 when it does not, -1 when the GPU
 * is not found. */
int media_gpu_route_vulkan_import(const struct media_gpu_route *gpu);
#ifdef __cplusplus
}
#endif
#endif
