/* Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: GPL-3.0-or-later */
#include <vlc/vlc.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <stdatomic.h>
static uint8_t *planes[3];
static unsigned width, height, bits;
static FILE *pixels;
static atomic_int ended;
static unsigned frames;
static unsigned setup(void **opaque, char *chroma, unsigned *w, unsigned *h,
                       unsigned *pitches, unsigned *lines)
{
    (void) opaque;
    memcpy(chroma, bits == 8 ? "I420" : bits == 10 ? "I0AL" : "I0CL", 4);
    /* vmem starts with coded alignment, so request the fixture display raster. */
    *w = width = 640;
    *h = height = 192;
    for (unsigned i = 0; i < 3; i++) {
        pitches[i] = (i ? width / 2 : width) * (bits > 8 ? 2 : 1);
        lines[i] = i ? height / 2 : height;
        free(planes[i]);
        if (posix_memalign((void **) &planes[i], 64, pitches[i] * lines[i]))
            return 0;
    }
    fprintf(stderr, "OUTPUT %.4s %ux%u bits=%u\n", chroma, width, height, bits);
    return 1;
}
static void *lock(void *opaque, void **out)
{
    (void) opaque;
    for (int i = 0; i < 3; i++) out[i] = planes[i];
    return NULL;
}
static void display(void *opaque, void *id)
{
    (void) opaque; (void) id;
    for (unsigned i = 0; i < width * height; i++) {
        uint16_t value = bits == 8 ? planes[0][i] : ((uint16_t *) planes[0])[i];
        fwrite(&value, 2, 1, pixels);
    }
    frames++;
}
static void event(const libvlc_event_t *event, void *opaque)
{
    (void) opaque;
    atomic_store(&ended, event->type == libvlc_MediaPlayerEncounteredError ? -1 : 1);
}
int main(int argc, char **argv)
{
    if (argc != 5) return 2;
    bits = atoi(argv[3]);
    pixels = fopen(argv[2], "wb");
    const char *args[] = {"--no-plugins-cache", "--no-audio", "--no-drop-late-frames", "--no-skip-frames", "--no-video-title-show", argv[4]};
    libvlc_instance_t *instance = libvlc_new(sizeof(args)/sizeof(args[0]), args);
    if (!instance) return 3;
    libvlc_media_t *media = libvlc_media_new_path(instance, argv[1]);
    char option[128];
    snprintf(option, sizeof(option), ":%s", argv[4] + 2);
    libvlc_media_add_option_flag(media, option, libvlc_media_option_trusted);
    libvlc_media_player_t *player = libvlc_media_player_new_from_media(media);
    libvlc_media_release(media);
    libvlc_video_set_callbacks(player, lock, NULL, display, NULL);
    libvlc_video_set_format_callbacks(player, setup, NULL);
    libvlc_event_manager_t *events = libvlc_media_player_event_manager(player);
    libvlc_event_attach(events, libvlc_MediaPlayerEndReached, event, NULL);
    libvlc_event_attach(events, libvlc_MediaPlayerEncounteredError, event, NULL);
    libvlc_media_player_play(player);
    for (int i = 0; i < 200 && !atomic_load(&ended); i++) usleep(100000);
    libvlc_media_player_stop(player);
    libvlc_media_player_release(player);
    libvlc_release(instance);
    fclose(pixels);
    for (int i = 0; i < 3; i++) free(planes[i]);
    fprintf(stderr, "PRESENTED %u frames\n", frames);
    return atomic_load(&ended) == 1 && frames ? 0 : 4;
}
