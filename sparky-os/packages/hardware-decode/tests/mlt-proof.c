/* Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: GPL-3.0-or-later */
#include <framework/mlt.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv)
{
    if (argc != 4 && argc != 5)
        return 2;
    mlt_factory_init(NULL);
    mlt_log_set_level(MLT_LOG_INFO);
    mlt_profile profile = mlt_profile_init(NULL);
    profile->width = 640;
    profile->height = 192;
    profile->frame_rate_num = 24;
    profile->frame_rate_den = 1;
    profile->progressive = 1;
    profile->sample_aspect_num = profile->sample_aspect_den = 1;
    mlt_producer producer = mlt_factory_producer(profile, "avformat", argv[1]);
    if (!producer)
        return 3;
    mlt_properties_set_int(MLT_PRODUCER_PROPERTIES(producer), "threads", 4);
    FILE *pixels = fopen(argv[2], "wb");
    const int bits = atoi(argv[3]);
    for (int n = 0; n < (argc == 5 ? atoi(argv[4]) : 48); n++) {
        mlt_frame frame = NULL;
        if (mlt_service_get_frame(MLT_PRODUCER_SERVICE(producer), &frame, 0))
            return 4;
        uint8_t *image = NULL;
        mlt_image_format format = bits > 8 ? mlt_image_yuv422p16 : mlt_image_yuv420p;
        int width = 640, height = 192;
        if (mlt_frame_get_image(frame, &image, &format, &width, &height, 0) || !image)
            return 5;
        if (bits > 8 && format != mlt_image_yuv422p16)
            return 6;
        for (int i = 0; i < width * height; i++) {
            uint16_t value = bits > 8 ? ((uint16_t *) image)[i] >> (16 - bits) : image[i];
            fwrite(&value, 2, 1, pixels);
        }
        printf("FRAME %d %d %d %s %d\n", n, width, height,
               mlt_properties_get(MLT_PRODUCER_PROPERTIES(producer), "meta.media.stereo3d.type"),
               mlt_properties_get_int(MLT_PRODUCER_PROPERTIES(producer), "meta.media.stereo3d.invert"));
        mlt_frame_close(frame);
    }
    fclose(pixels);
    mlt_producer_close(producer);
    mlt_profile_close(profile);
    mlt_factory_close();
    return 0;
}
