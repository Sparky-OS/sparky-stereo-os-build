/* Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: MIT */
#include <media-gpu-route-ffmpeg.h>
#include <libavformat/avformat.h>
#include <stdio.h>
int main(int argc, char **argv)
{
    if (argc != 3) return 2;
    AVFormatContext *input = NULL;
    if (avformat_open_input(&input, argv[1], NULL, NULL) < 0 || avformat_find_stream_info(input, NULL) < 0) return 3;
    int stream = av_find_best_stream(input, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
    if (stream < 0) return 4;
    const AVCodecParameters *p = input->streams[stream]->codecpar;
    struct media_gpu_decoder choice = {0};
    int result = media_gpu_route_av(p->codec_id, p->profile, p->format, p->width, p->height, &choice);
    printf("codec=%s profile=%d format=%s result=%d backend=%d gpu=%s device=%s\n", avcodec_get_name(p->codec_id), p->profile, av_get_pix_fmt_name(p->format), result, choice.backend, choice.gpu.name, choice.device);
    const char *expected = argv[2];
    int correct = result == 0 ? !strcmp(expected, "software") : result == 1 &&
        (choice.backend == MEDIA_GPU_VAAPI ? !strcmp(expected, "vaapi") : !strcmp(expected, "cuda"));
    avformat_close_input(&input);
    return !correct;
}
