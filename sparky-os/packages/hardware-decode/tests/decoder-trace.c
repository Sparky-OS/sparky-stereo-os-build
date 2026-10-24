/* Test observer only, never installed in a package. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <libavcodec/avcodec.h>
#include <libavutil/hwcontext.h>
#include <libavutil/pixdesc.h>
#include <libavutil/stereo3d.h>
int avcodec_receive_frame(AVCodecContext *context, AVFrame *frame)
{
    void *library = dlopen("libavcodec.so.63", RTLD_NOW | RTLD_NOLOAD);
    int (*receive)(AVCodecContext *, AVFrame *) = library ? dlsym(library, "avcodec_receive_frame") : NULL;
    if (!receive)
        _exit(70);
    int result = receive(context, frame);
    dlclose(library);
    const char *path = getenv("DECODER_TRACE");
    if (result >= 0 && path && context->codec_type == AVMEDIA_TYPE_VIDEO) {
        const AVFrameSideData *side = av_frame_get_side_data(frame, AV_FRAME_DATA_STEREO3D);
        const AVStereo3D *stereo = side ? (const AVStereo3D *) side->data : NULL;
        const AVPixFmtDescriptor *output = av_pix_fmt_desc_get(frame->format);
        int is_hardware = output && (output->flags & AV_PIX_FMT_FLAG_HWACCEL);
        int sw = is_hardware ? context->sw_pix_fmt : frame->format;
        if (frame->hw_frames_ctx)
            sw = ((AVHWFramesContext *) frame->hw_frames_ctx->data)->sw_format;
        const AVPixFmtDescriptor *desc = av_pix_fmt_desc_get(sw);
        char line[512];
        int size = snprintf(line, sizeof(line), "%s,%lld,%s,%s,%d,%d,%d,%d\n",
                            context->codec->name, (long long) frame->best_effort_timestamp,
                            av_get_pix_fmt_name(frame->format), av_get_pix_fmt_name(sw),
                            desc ? desc->comp[0].depth : 0, stereo ? (int) stereo->type : -1,
                            stereo ? stereo->flags : 0, !!is_hardware);
        int file = open(path, O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (file >= 0) {
            ssize_t written = write(file, line, size);
            (void) written;
            close(file);
        }
    }
    return result;
}

int av_frame_copy_props(AVFrame *destination, const AVFrame *source)
{
    void *library = dlopen("libavutil.so.61", RTLD_NOW | RTLD_NOLOAD);
    int (*copy)(AVFrame *, const AVFrame *) = library ? dlsym(library, "av_frame_copy_props") : NULL;
    if (!copy)
        _exit(70);
    int result = copy(destination, source);
    dlclose(library);
    const char *path = getenv("DECODER_COPY_PIXELS");
    const AVPixFmtDescriptor *src = av_pix_fmt_desc_get(source->format);
    const AVPixFmtDescriptor *dst = av_pix_fmt_desc_get(destination->format);
    if (result >= 0 && path && src && dst && (src->flags & AV_PIX_FMT_FLAG_HWACCEL)
        && !(dst->flags & (AV_PIX_FMT_FLAG_HWACCEL | AV_PIX_FMT_FLAG_RGB))
        && destination->data[0] && destination->width > 0 && destination->height > 0) {
        int file = open(path, O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (file < 0)
            _exit(71);
        uint16_t *row = malloc(destination->width * sizeof(*row));
        for (int y = 0; y < destination->height; y++) {
            const uint8_t *data = destination->data[0] + y * destination->linesize[0];
            for (int x = 0; x < destination->width; x++) {
                const uint8_t *sample = data + x * dst->comp[0].step + dst->comp[0].offset;
                row[x] = (dst->comp[0].depth > 8 ? sample[0] | (sample[1] << 8) : sample[0]) >> dst->comp[0].shift;
            }
            ssize_t written = write(file, row, destination->width * sizeof(*row));
            (void) written;
        }
        free(row);
        close(file);
        const char *trace = getenv("DECODER_COPY_TRACE");
        if (trace) {
            const AVFrameSideData *side = av_frame_get_side_data(destination, AV_FRAME_DATA_STEREO3D);
            const AVStereo3D *stereo = side ? (const AVStereo3D *) side->data : NULL;
            char line[256];
            int size = snprintf(line, sizeof(line), "%lld,%s,%d,%d,%d\n",
                                (long long) destination->best_effort_timestamp, dst->name,
                                dst->comp[0].depth, stereo ? (int) stereo->type : -1,
                                stereo ? stereo->flags : 0);
            file = open(trace, O_WRONLY | O_CREAT | O_APPEND, 0600);
            if (file >= 0) {
                ssize_t written = write(file, line, size);
                (void) written;
                close(file);
            }
        }
    }
    return result;
}
