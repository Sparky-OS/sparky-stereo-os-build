// SPDX-License-Identifier: MIT
// Isolated KWin input for the paper depth rig.
#include <linux/input-event-codes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <wayland-client.h>

#include "fake-input-client.h"

static struct org_kde_kwin_fake_input *input;

static void announced(void *data, struct wl_registry *registry, uint32_t name,
                      const char *interface, uint32_t version)
{
    (void)data;
    if (!strcmp(interface, org_kde_kwin_fake_input_interface.name) && version >= 4)
        input = wl_registry_bind(registry, name, &org_kde_kwin_fake_input_interface, 4);
}

static void removed(void *data, struct wl_registry *registry, uint32_t name)
{
    (void)data;
    (void)registry;
    (void)name;
}

static void key(unsigned code, unsigned pressed)
{
    org_kde_kwin_fake_input_keyboard_key(input, code, pressed);
}

int main(int argc, char **argv)
{
    // The rig's private Wayland socket is always named sub.
    const char *socket = getenv("WAYLAND_DISPLAY");
    if (!socket || strcmp(socket, "sub") || argc < 3)
        return 2;

    struct wl_display *display = wl_display_connect(socket);
    if (!display)
        return 3;
    struct wl_registry *registry = wl_display_get_registry(display);
    const struct wl_registry_listener listener = {announced, removed};
    wl_registry_add_listener(registry, &listener, NULL);
    wl_display_roundtrip(display);
    if (!input) {
        fputs("KWin did not advertise fake input\n", stderr);
        wl_display_disconnect(display);
        return 4;
    }
    org_kde_kwin_fake_input_authenticate(input, "paper-depth proof", "isolated compositor input");
    wl_display_roundtrip(display);

    int result = 0;
    if (argc == 4 && (!strcmp(argv[1], "click") || !strcmp(argv[1], "move"))) {
        org_kde_kwin_fake_input_pointer_motion_absolute(input, wl_fixed_from_double(atof(argv[2])),
                                                      wl_fixed_from_double(atof(argv[3])));
        wl_display_roundtrip(display);
        if (!strcmp(argv[1], "click")) {
            org_kde_kwin_fake_input_button(input, BTN_LEFT, WL_POINTER_BUTTON_STATE_PRESSED);
            org_kde_kwin_fake_input_button(input, BTN_LEFT, WL_POINTER_BUTTON_STATE_RELEASED);
        }
    } else if (argc == 3 && !strcmp(argv[1], "scroll")) {
        org_kde_kwin_fake_input_axis(input, WL_POINTER_AXIS_VERTICAL_SCROLL, wl_fixed_from_double(atof(argv[2])));
    } else if (!strcmp(argv[1], "keys")) {
        for (int i = 2; i < argc; i++) {
            const int code = atoi(argv[i]);
            if (code < 0) {
                key(-code, 0);
            } else if (argv[i][0] == '+') {
                key(code, 1);
            } else {
                key(code, 1);
                key(code, 0);
            }
            wl_display_roundtrip(display);
            usleep(70000);
        }
    } else {
        result = 2;
    }

    wl_display_roundtrip(display);
    wl_display_disconnect(display);
    return result;
}
