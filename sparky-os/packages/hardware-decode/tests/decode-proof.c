/* Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: GPL-3.0-or-later */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/hwcontext.h>
#include <libavutil/imgutils.h>
#include <libavutil/pixdesc.h>
#include <libavutil/stereo3d.h>
#include <libswscale/swscale.h>

static enum AVPixelFormat hardware = AV_PIX_FMT_NONE;
static int hardware_frames;
static int decline_after_probe;
static FILE *pixels;
static AVCodecContext *decoder;

static enum AVPixelFormat choose(AVCodecContext *ctx, const enum AVPixelFormat *formats)
{
    for (const enum AVPixelFormat *p = formats; *p != AV_PIX_FMT_NONE; p++)
        if (*p == hardware) {
            if (decline_after_probe) {
                AVBufferRef *parameters = NULL;
                if (avcodec_get_hw_frames_parameters(ctx, ctx->hw_device_ctx, *p, &parameters) < 0)
                    exit(11);
                av_buffer_unref(&parameters);
                return ctx->sw_pix_fmt;
            }
            return *p;
        }
    return avcodec_default_get_format(ctx, formats);
}

static void receive(void)
{
    AVFrame *frame = av_frame_alloc();
    while (avcodec_receive_frame(decoder, frame) >= 0) {
        AVFrame *sw = frame;
        const AVFrameSideData *side = av_frame_get_side_data(frame, AV_FRAME_DATA_STEREO3D);
        const AVStereo3D *stereo = side ? (const AVStereo3D *) side->data : NULL;
        if (frame->hw_frames_ctx) {
            hardware_frames++;
            sw = av_frame_alloc();
            if (av_hwframe_transfer_data(sw, frame, 0) < 0)
                exit(4);
        }
        enum AVPixelFormat format = decoder->sw_pix_fmt;
        int size = av_image_get_buffer_size(format, sw->width, sw->height, 1);
        uint8_t *buffer = av_malloc(size);
        uint8_t *planes[4];
        int strides[4];
        av_image_fill_arrays(planes, strides, buffer, format, sw->width, sw->height, 1);
        struct SwsContext *sws = sws_getContext(sw->width, sw->height, sw->format,
                                               sw->width, sw->height, format,
                                               SWS_POINT | SWS_BITEXACT, NULL, NULL, NULL);
        if (!sws || sws_scale(sws, (const uint8_t * const *) sw->data, sw->linesize,
                               0, sw->height, planes, strides) != sw->height)
            exit(5);
        fwrite(buffer, 1, size, pixels);
        const AVPixFmtDescriptor *desc = av_pix_fmt_desc_get(sw->format);
        printf("%lld,%s,%d,%d,%d,%d\n", (long long) frame->best_effort_timestamp,
               av_get_pix_fmt_name(sw->format), desc->comp[0].depth,
               stereo ? (int) stereo->type : -1, stereo ? stereo->flags : 0,
               frame->hw_frames_ctx != NULL);
        sws_freeContext(sws);
        av_free(buffer);
        if (sw != frame)
            av_frame_free(&sw);
        av_frame_unref(frame);
    }
    av_frame_free(&frame);
}

int main(int argc, char **argv)
{
    if (argc != 5)
        return 2;
    AVFormatContext *input = NULL;
    if (avformat_open_input(&input, argv[1], NULL, NULL) < 0
        || avformat_find_stream_info(input, NULL) < 0)
        return 3;
    int index = av_find_best_stream(input, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
    const AVCodec *codec = avcodec_find_decoder(input->streams[index]->codecpar->codec_id);
    decoder = avcodec_alloc_context3(codec);
    avcodec_parameters_to_context(decoder, input->streams[index]->codecpar);
    decoder->thread_count = 4;
    if (strcmp(argv[2], "software")) {
        decline_after_probe = !strcmp(argv[2], "cuda-probe-software");
        enum AVHWDeviceType type = av_hwdevice_find_type_by_name(decline_after_probe ? "cuda" : argv[2]);
        for (int i = 0;; i++) {
            const AVCodecHWConfig *config = avcodec_get_hw_config(codec, i);
            if (!config)
                return 6;
            if (config->device_type == type) {
                hardware = config->pix_fmt;
                break;
            }
        }
        if (av_hwdevice_ctx_create(&decoder->hw_device_ctx, type, NULL, NULL, 0) < 0)
            return 7;
        decoder->get_format = choose;
    }
    if (avcodec_open2(decoder, codec, NULL) < 0)
        return 8;
    pixels = fopen(argv[3], "wb");
    AVPacket *packet = av_packet_alloc();
    while (av_read_frame(input, packet) >= 0) {
        if (packet->stream_index == index) {
            if (avcodec_send_packet(decoder, packet) < 0)
                return 9;
            receive();
        }
        av_packet_unref(packet);
    }
    avcodec_send_packet(decoder, NULL);
    receive();
    fclose(pixels);
    fprintf(stderr, "Hardware frames: %d\n", hardware_frames);
    int require_hardware = atoi(argv[4]);
    av_packet_free(&packet);
    avcodec_free_context(&decoder);
    avformat_close_input(&input);
    return require_hardware && !hardware_frames ? 10 : 0;
}
