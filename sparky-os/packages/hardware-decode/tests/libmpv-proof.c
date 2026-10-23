/* Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: GPL-3.0-or-later */
#include <mpv/client.h>
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv)
{
    if (argc != 2) return 2;
    mpv_handle *player = mpv_create();
    mpv_set_option_string(player, "config", "no");
    mpv_set_option_string(player, "vo", "null");
    mpv_set_option_string(player, "ao", "null");
    mpv_set_option_string(player, "untimed", "yes");
    if (mpv_initialize(player) < 0) return 3;
    const char *command[] = {"loadfile", argv[1], NULL};
    if (mpv_command(player, command) < 0) return 4;
    int frames = 0, success = 0;
    mpv_observe_property(player, 0, "hwdec-current", MPV_FORMAT_STRING);
    for (int i = 0; i < 10000; i++) {
        mpv_event *event = mpv_wait_event(player, 2);
        if (event->event_id == MPV_EVENT_NONE) break;
        if (event->event_id == MPV_EVENT_VIDEO_RECONFIG) {
            char *hw = mpv_get_property_string(player, "hwdec-current");
            printf("HWDEC %s\n", hw ? hw : "unknown");
            mpv_free(hw);
            frames++;
        }
        if (event->event_id == MPV_EVENT_END_FILE) {
            mpv_event_end_file *end = event->data;
            success = end->reason == MPV_END_FILE_REASON_EOF;
            break;
        }
    }
    mpv_terminate_destroy(player);
    return success && frames ? 0 : 5;
}
