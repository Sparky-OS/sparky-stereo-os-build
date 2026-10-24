/* Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: MIT */
#ifndef MEDIA_GPU_ROUTE_FFMPEG_H
#define MEDIA_GPU_ROUTE_FFMPEG_H
#include "media-gpu-route.h"
#ifdef __cplusplus
extern "C" {
#endif
#include <libavcodec/avcodec.h>
#include <libavutil/pixdesc.h>
#ifdef __cplusplus
}
#endif
#include <string.h>
static inline int media_gpu_route_av_frames(enum AVCodecID codec, int profile, enum AVPixelFormat format,
                                           int width, int height, enum media_gpu_frames frames,
                                           struct media_gpu_decoder *decoder)
{
    struct media_gpu_video video;
    memset(&video, 0, sizeof(video));
    /* Software, whatever the codec, when the pictures would be copied back
     * and nobody allowed that. */
    if (frames == MEDIA_GPU_FRAMES_COPY && !media_gpu_route_copy_back()) {
        memset(decoder, 0, sizeof(*decoder));
        return 0;
    }
    switch (codec) {
    case AV_CODEC_ID_H264: video.codec = MEDIA_GPU_CODEC_H264; break;
    case AV_CODEC_ID_HEVC: video.codec = MEDIA_GPU_CODEC_HEVC; break;
    case AV_CODEC_ID_VP8: video.codec = MEDIA_GPU_CODEC_VP8; break;
    case AV_CODEC_ID_VP9: video.codec = MEDIA_GPU_CODEC_VP9; break;
    case AV_CODEC_ID_AV1: video.codec = MEDIA_GPU_CODEC_AV1; break;
    case AV_CODEC_ID_MPEG1VIDEO: video.codec = MEDIA_GPU_CODEC_MPEG1; break;
    case AV_CODEC_ID_MPEG2VIDEO: video.codec = MEDIA_GPU_CODEC_MPEG2; break;
    case AV_CODEC_ID_MPEG4: video.codec = MEDIA_GPU_CODEC_MPEG4; break;
    case AV_CODEC_ID_VC1: case AV_CODEC_ID_WMV3: video.codec = MEDIA_GPU_CODEC_VC1; break;
    case AV_CODEC_ID_MJPEG: video.codec = MEDIA_GPU_CODEC_MJPEG; break;
    default: return -1;
    }
    const AVPixFmtDescriptor *desc = av_pix_fmt_desc_get(format);
    if (!desc)
        return -1;
    video.profile = profile;
    video.bits = desc->comp[0].depth;
    video.components = desc->nb_components;
    video.log2_chroma_w = desc->log2_chroma_w;
    video.log2_chroma_h = desc->log2_chroma_h;
    video.rgb = !!(desc->flags & AV_PIX_FMT_FLAG_RGB);
    video.width = width;
    video.height = height;
    return media_gpu_route_decoder_frames(&video, frames, decoder);
}
/* For a caller that copies its pictures back. */
static inline int media_gpu_route_av(enum AVCodecID codec, int profile, enum AVPixelFormat format,
                                    int width, int height, struct media_gpu_decoder *decoder)
{
    return media_gpu_route_av_frames(codec, profile, format, width, height, MEDIA_GPU_FRAMES_COPY, decoder);
}
#endif
