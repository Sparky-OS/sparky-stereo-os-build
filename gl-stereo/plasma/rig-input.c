// SPDX-License-Identifier: GPL-2.0-or-later
#include "fake-input-client-protocol.h"
#include <wayland-client.h>
#include <string.h>
#include <stdlib.h>
#include <linux/input-event-codes.h>
static struct org_kde_kwin_fake_input *input;
static void global(void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version)
{
    if (!strcmp(interface, "org_kde_kwin_fake_input"))
        input = wl_registry_bind(registry, name, &org_kde_kwin_fake_input_interface, version < 4 ? version : 4);
}
static void removed(void *data, struct wl_registry *registry, uint32_t name) {}
int main(int argc, char **argv)
{
    if (!getenv("GL_STEREO_PRIVATE_RIG")) return 2;
    struct wl_display *display = wl_display_connect(NULL);
    if (!display) return 3;
    struct wl_registry *registry = wl_display_get_registry(display);
    static const struct wl_registry_listener listener = {global, removed};
    wl_registry_add_listener(registry, &listener, NULL);
    wl_display_roundtrip(display);
    if (!input) return 4;
    org_kde_kwin_fake_input_authenticate(input, "gl-stereo-test", "private container integration test");
    unsigned key = argc > 1 ? atoi(argv[1]) : KEY_LEFTSHIFT;
    org_kde_kwin_fake_input_keyboard_key(input, key, WL_KEYBOARD_KEY_STATE_PRESSED);
    org_kde_kwin_fake_input_keyboard_key(input, key, WL_KEYBOARD_KEY_STATE_RELEASED);
    wl_display_roundtrip(display);
    wl_display_disconnect(display);
    return 0;
}
