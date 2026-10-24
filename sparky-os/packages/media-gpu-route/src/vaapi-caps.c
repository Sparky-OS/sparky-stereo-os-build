/* Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: MIT */
#include "gpu-private.h"
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>
#include <va/va.h>
#include <va/va_drm.h>

static VAProfile profile_for(const struct media_gpu_video *v)
{
    switch (v->codec) {
    case MEDIA_GPU_CODEC_H264:
        if (v->profile < 0) return VAProfileNone;
        switch (v->profile & 255) {
        case 66: return VAProfileH264ConstrainedBaseline;
        case 77: return VAProfileH264Main;
        case 100: return VAProfileH264High;
#if VA_CHECK_VERSION(1, 18, 0)
        case 110: return VAProfileH264High10;
#endif
        default: return VAProfileNone;
        }
    case MEDIA_GPU_CODEC_HEVC:
        if (v->log2_chroma_w == 1 && v->log2_chroma_h == 1)
            return v->bits > 10 ? VAProfileHEVCMain12 : v->bits > 8 ? VAProfileHEVCMain10 : VAProfileHEVCMain;
        if (v->log2_chroma_w == 1 && v->log2_chroma_h == 0)
            return v->bits > 10 ? VAProfileHEVCMain422_12 : VAProfileHEVCMain422_10;
        if (!v->log2_chroma_w && !v->log2_chroma_h)
            return v->bits > 10 ? VAProfileHEVCMain444_12 : v->bits > 8 ? VAProfileHEVCMain444_10 : VAProfileHEVCMain444;
        return VAProfileNone;
    case MEDIA_GPU_CODEC_VP8: return VAProfileVP8Version0_3;
    case MEDIA_GPU_CODEC_VP9:
        if (v->profile >= 0 && v->profile <= 3) {
            const VAProfile profiles[] = { VAProfileVP9Profile0, VAProfileVP9Profile1, VAProfileVP9Profile2, VAProfileVP9Profile3 };
            return profiles[v->profile];
        }
        return VAProfileNone;
    case MEDIA_GPU_CODEC_AV1:
        return v->profile == 0 ? VAProfileAV1Profile0 : v->profile == 1 ? VAProfileAV1Profile1 : VAProfileNone;
    case MEDIA_GPU_CODEC_MPEG2:
        return v->profile == 5 ? VAProfileMPEG2Simple : v->profile == 4 ? VAProfileMPEG2Main : VAProfileNone;
    case MEDIA_GPU_CODEC_MPEG4:
        return v->profile == 0 ? VAProfileMPEG4Simple : v->profile == 3 ? VAProfileMPEG4Main : v->profile == 15 ? VAProfileMPEG4AdvancedSimple : VAProfileNone;
    case MEDIA_GPU_CODEC_VC1:
        return v->profile == 0 ? VAProfileVC1Simple : v->profile == 1 ? VAProfileVC1Main : v->profile == 3 ? VAProfileVC1Advanced : VAProfileNone;
    case MEDIA_GPU_CODEC_MJPEG: return VAProfileJPEGBaseline;
    default: return VAProfileNone;
    }
}

static unsigned rt_format(const struct media_gpu_video *v)
{
    if (v->log2_chroma_w == 1 && v->log2_chroma_h == 1)
        return v->bits > 10 ? VA_RT_FORMAT_YUV420_12 : v->bits > 8 ? VA_RT_FORMAT_YUV420_10 : VA_RT_FORMAT_YUV420;
    if (v->log2_chroma_w == 1 && v->log2_chroma_h == 0)
        return v->bits > 10 ? VA_RT_FORMAT_YUV422_12 : v->bits > 8 ? VA_RT_FORMAT_YUV422_10 : VA_RT_FORMAT_YUV422;
    if (!v->log2_chroma_w && !v->log2_chroma_h)
        return v->bits > 10 ? VA_RT_FORMAT_YUV444_12 : v->bits > 8 ? VA_RT_FORMAT_YUV444_10 : VA_RT_FORMAT_YUV444;
    return 0;
}

int media_gpu_vaapi_supports(const struct media_gpu_video *v, const struct media_gpu_route *gpu)
{
    VAProfile profile = profile_for(v);
    unsigned required = rt_format(v);
    if (profile == VAProfileNone || !required)
        return -1;
    int fd = open(gpu->render_node, O_RDWR | O_CLOEXEC);
    if (fd < 0) return 0;
    VADisplay display = vaGetDisplayDRM(fd);
    int major, minor, result = 0;
    VAProfile *profiles = NULL;
    if (!display || vaInitialize(display, &major, &minor) != VA_STATUS_SUCCESS)
        goto done;
    int count = vaMaxNumProfiles(display);
    profiles = calloc(count > 0 ? count : 1, sizeof(*profiles));
    if (!profiles) { result = -1; goto terminate; }
    if (vaQueryConfigProfiles(display, profiles, &count) != VA_STATUS_SUCCESS) {
        result = -1;
        goto terminate;
    }
    for (int i = 0; i < count; i++) {
        if (profiles[i] != profile) continue;
        VAConfigAttrib attrs[] = { { .type = VAConfigAttribRTFormat },
            { .type = VAConfigAttribMaxPictureWidth }, { .type = VAConfigAttribMaxPictureHeight } };
        if (vaGetConfigAttributes(display, profile, VAEntrypointVLD, attrs, 3) != VA_STATUS_SUCCESS)
            break;
        result = attrs[0].value != VA_ATTRIB_NOT_SUPPORTED && (attrs[0].value & required) == required
            && (attrs[1].value == VA_ATTRIB_NOT_SUPPORTED || v->width <= (int) attrs[1].value)
            && (attrs[2].value == VA_ATTRIB_NOT_SUPPORTED || v->height <= (int) attrs[2].value);
        break;
    }
terminate:
    free(profiles);
    vaTerminate(display);
done:
    close(fd);
    return result;
}
