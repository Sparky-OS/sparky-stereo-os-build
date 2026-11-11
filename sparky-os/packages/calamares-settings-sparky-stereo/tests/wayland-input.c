/* SPDX-License-Identifier: MIT
 * Isolated KWin test input only; never connect this to a person's session. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <wayland-client.h>
#include "fake-input-client.h"
static struct org_kde_kwin_fake_input *input;
static void global(void *data, struct wl_registry *registry, uint32_t name,
                   const char *interface, uint32_t version)
{
    (void)data;
    if (!strcmp(interface, "org_kde_kwin_fake_input"))
        input = wl_registry_bind(registry, name, &org_kde_kwin_fake_input_interface,
                                 version < 4 ? version : 4);
}
static void removed(void *data, struct wl_registry *registry, uint32_t name)
{ (void)data; (void)registry; (void)name; }
int main(int argc, char **argv)
{
    if (argc < 2) return 2;
    struct wl_display *display = wl_display_connect(NULL);
    if (!display) return 3;
    struct wl_registry *registry = wl_display_get_registry(display);
    const struct wl_registry_listener listener = {global, removed};
    wl_registry_add_listener(registry, &listener, NULL);
    wl_display_roundtrip(display);
    if (!input) return 4;
    org_kde_kwin_fake_input_authenticate(input, "installer-test", "private KWin licence proof");
    wl_display_roundtrip(display);
    for (int i = 1; i < argc; ++i) {
        unsigned key = (unsigned)strtoul(argv[i], NULL, 10);
        org_kde_kwin_fake_input_keyboard_key(input, key, WL_KEYBOARD_KEY_STATE_PRESSED);
        org_kde_kwin_fake_input_keyboard_key(input, key, WL_KEYBOARD_KEY_STATE_RELEASED);
        wl_display_roundtrip(display);
        usleep(100000);
    }
    wl_display_disconnect(display);
    return 0;
}
