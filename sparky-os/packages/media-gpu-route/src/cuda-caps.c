/* Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: MIT */
#include "gpu-private.h"
#include <stdio.h>
#include <sys/sysmacros.h>
#include <xf86drm.h>
#include <ffnvcodec/dynlink_loader.h>

static int codec_for(enum media_gpu_codec codec)
{
    switch (codec) {
    case MEDIA_GPU_CODEC_H264: return cudaVideoCodec_H264;
    case MEDIA_GPU_CODEC_HEVC: return cudaVideoCodec_HEVC;
    case MEDIA_GPU_CODEC_VP8: return cudaVideoCodec_VP8;
    case MEDIA_GPU_CODEC_VP9: return cudaVideoCodec_VP9;
    case MEDIA_GPU_CODEC_AV1: return cudaVideoCodec_AV1;
    case MEDIA_GPU_CODEC_MPEG1: return cudaVideoCodec_MPEG1;
    case MEDIA_GPU_CODEC_MPEG2: return cudaVideoCodec_MPEG2;
    case MEDIA_GPU_CODEC_MPEG4: return cudaVideoCodec_MPEG4;
    case MEDIA_GPU_CODEC_VC1: return cudaVideoCodec_VC1;
    case MEDIA_GPU_CODEC_MJPEG: return cudaVideoCodec_JPEG;
    default: return -1;
    }
}

int media_gpu_cuda_supports(const struct media_gpu_video *v, const struct media_gpu_route *gpu, char selector[128])
{
    int codec = codec_for(v->codec);
    if (codec < 0) return -1;
    if (v->codec == MEDIA_GPU_CODEC_VC1 && v->profile == 2)
        return -1;
    /* NVDEC reports depth and chroma capabilities, not these profile tools. */
    if (v->codec == MEDIA_GPU_CODEC_H264 && v->profile >= 0
        && (v->profile & 255) != 66 && (v->profile & 255) != 77
        && (v->profile & 255) != 88 && (v->profile & 255) != 100
        && (v->profile & 255) != 110 && (v->profile & 255) != 122
        && (v->profile & 255) != 244)
        return -1;
    if (v->codec == MEDIA_GPU_CODEC_HEVC && v->profile > 4)
        return -1;
    int chroma = v->log2_chroma_w == 1 && v->log2_chroma_h == 1 ? cudaVideoChromaFormat_420
        : v->log2_chroma_w == 1 && v->log2_chroma_h == 0 ? cudaVideoChromaFormat_422
        : !v->log2_chroma_w && !v->log2_chroma_h ? cudaVideoChromaFormat_444 : -1;
    // The installed nv-codec-headers API has no 4:2:2 output surface.
    if (chroma < 0 || chroma == cudaVideoChromaFormat_422) return 0;
    CudaFunctions *cuda = NULL;
    CuvidFunctions *cuvid = NULL;
    drmDevicePtr drm = NULL;
    CUcontext context = NULL;
    CUdevice device;
    int result = 0;
    if (cuda_load_functions(&cuda, NULL) < 0 || cuvid_load_functions(&cuvid, NULL) < 0)
        goto done;
    if (cuda->cuInit(0) != CUDA_SUCCESS || !cuda->cuDeviceGetByPCIBusId)
        goto done;
    if (drmGetDeviceFromDevId((dev_t) gpu->drm_device, 0, &drm) || drm->bustype != DRM_BUS_PCI)
        goto done;
    char pci[32];
    snprintf(pci, sizeof(pci), "%04x:%02x:%02x.%x", drm->businfo.pci->domain,
             drm->businfo.pci->bus, drm->businfo.pci->dev, drm->businfo.pci->func);
    if (cuda->cuDeviceGetByPCIBusId(&device, pci) != CUDA_SUCCESS)
        goto done;
    if (cuda->cuCtxCreate(&context, CU_CTX_SCHED_BLOCKING_SYNC, device) != CUDA_SUCCESS)
        goto done;
    CUVIDDECODECAPS caps = { .eCodecType = codec, .eChromaFormat = chroma,
        .nBitDepthMinus8 = v->bits - 8 };
    if (!cuvid->cuvidGetDecoderCaps || cuvid->cuvidGetDecoderCaps(&caps) != CUDA_SUCCESS) {
        result = -1;
        goto pop;
    }
    int output = chroma == cudaVideoChromaFormat_420
        ? (v->bits > 8 ? cudaVideoSurfaceFormat_P016 : cudaVideoSurfaceFormat_NV12)
        : chroma == cudaVideoChromaFormat_444
        ? (v->bits > 8 ? cudaVideoSurfaceFormat_YUV444_16Bit : cudaVideoSurfaceFormat_YUV444)
        : cudaVideoSurfaceFormat_NV12;
    uint64_t blocks = ((uint64_t) v->width + 15) / 16 * (((uint64_t) v->height + 15) / 16);
    result = caps.bIsSupported && (caps.nOutputFormatMask & (1u << output))
        && (unsigned) v->width >= caps.nMinWidth && (unsigned) v->width <= caps.nMaxWidth
        && (unsigned) v->height >= caps.nMinHeight && (unsigned) v->height <= caps.nMaxHeight
        && blocks <= caps.nMaxMBCount;
    if (result)
        snprintf(selector, 128, "%d", device);
pop:
    { CUcontext popped; cuda->cuCtxPopCurrent(&popped); }
    cuda->cuCtxDestroy(context);
done:
    if (drm) drmFreeDevice(&drm);
    cuvid_free_functions(&cuvid);
    cuda_free_functions(&cuda);
    return result;
}
