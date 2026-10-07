// usage: fi <x> <y> [click]   moves the pointer to the absolute position (screen px), optionally left-clicks (KWIN fake input)
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
    if (!fi) { fprintf(stderr, "no fake input\n"); return 3; }
    org_kde_kwin_fake_input_authenticate(fi, "fi", "test");
    org_kde_kwin_fake_input_pointer_motion_absolute(fi, wl_fixed_from_double(atof(argv[1])), wl_fixed_from_double(atof(argv[2])));
    wl_display_roundtrip(d);
    usleep(300000);
    if (argc > 5 && !strcmp(argv[3], "drag")) {
        double x2 = atof(argv[4]), y2 = atof(argv[5]), x1 = atof(argv[1]), y1 = atof(argv[2]);
        org_kde_kwin_fake_input_button(fi, 0x110, 1); wl_display_roundtrip(d); usleep(200000);
        for (int i = 1; i <= 20; i++) {
            org_kde_kwin_fake_input_pointer_motion_absolute(fi, wl_fixed_from_double(x1 + (x2 - x1) * i / 20), wl_fixed_from_double(y1 + (y2 - y1) * i / 20));
            wl_display_roundtrip(d); usleep(100000);
        }
        usleep(500000);
        org_kde_kwin_fake_input_button(fi, 0x110, 0); wl_display_roundtrip(d);
        return 0;
    }
    if (argc > 3) {
        org_kde_kwin_fake_input_button(fi, 0x110, 1); wl_display_roundtrip(d); usleep(80000);
        org_kde_kwin_fake_input_button(fi, 0x110, 0); wl_display_roundtrip(d);
    }
    if (argc > 4) {
        usleep(80000);
        org_kde_kwin_fake_input_button(fi, 0x110, 1); wl_display_roundtrip(d); usleep(80000);
        org_kde_kwin_fake_input_button(fi, 0x110, 0); wl_display_roundtrip(d);
    }
    wl_display_roundtrip(d);
    return 0;
}
