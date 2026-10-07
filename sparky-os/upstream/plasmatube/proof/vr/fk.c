// usage: fk <linux key code> [<count>]   presses and releases a key (KWin fake input), count times 200 ms apart; 105 Left, 106 Right, 103 Up, 108 Down
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <wayland-client.h>
#include "fake-input-client-protocol.h"
static struct org_kde_kwin_fake_input *fi;
static void reg(void *d, struct wl_registry *r, uint32_t n, const char *i, uint32_t v) {
    if (!strcmp(i, "org_kde_kwin_fake_input")) fi = wl_registry_bind(r, n, &org_kde_kwin_fake_input_interface, v < 4 ? v : 4);
}
static void rem(void *d, struct wl_registry *r, uint32_t n) {}
static const struct wl_registry_listener rl = {reg, rem};
int main(int argc, char **argv) {
    struct wl_display *d = wl_display_connect(NULL);
    if (!d) return 2;
    struct wl_registry *r = wl_display_get_registry(d);
    wl_registry_add_listener(r, &rl, NULL);
    wl_display_roundtrip(d);
    if (!fi) return 3;
    org_kde_kwin_fake_input_authenticate(fi, "fk", "test");
    int n = argc > 2 ? atoi(argv[2]) : 1;
    for (int i = 0; i < n; i++) {
        org_kde_kwin_fake_input_keyboard_key(fi, atoi(argv[1]), 1); wl_display_roundtrip(d); usleep(60000);
        org_kde_kwin_fake_input_keyboard_key(fi, atoi(argv[1]), 0); wl_display_roundtrip(d); usleep(200000);
    }
    return 0;
}
