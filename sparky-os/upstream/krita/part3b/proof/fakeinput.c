/* Test aid: drives KWin's org_kde_kwin_fake_input from a script.
 * usage: fakeinput <cmd> ...   with cmd: move X Y | click | press | release | type TEXT | key KEYCODE | sleep MS | drag X1 Y1 X2 Y2 */
#include <wayland-client.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "fake-input-client-protocol.h"
static struct org_kde_kwin_fake_input *fi;
static void reg(void *d, struct wl_registry *r, uint32_t id, const char *iface, uint32_t v)
{ if (getenv("FI_LIST")) fprintf(stderr, "global %s\n", iface); if (!strcmp(iface, "org_kde_kwin_fake_input")) fi = wl_registry_bind(r, id, &org_kde_kwin_fake_input_interface, v < 6 ? v : 6); }
static void rem(void *d, struct wl_registry *r, uint32_t id) {}
static const struct wl_registry_listener rl = { reg, rem };
static struct wl_display *dpy;
static void flush(void) { wl_display_roundtrip(dpy); }
static void mv(double x, double y) { org_kde_kwin_fake_input_pointer_motion_absolute(fi, wl_fixed_from_double(x), wl_fixed_from_double(y)); flush(); usleep(80000); }
static int bcode = 0x110;
static void btn(int s) { org_kde_kwin_fake_input_button(fi, bcode, s); flush(); usleep(80000); }
int main(int argc, char **argv)
{
    dpy = wl_display_connect(NULL); if (!dpy) { fprintf(stderr, "no wayland display\n"); return 1; }
    struct wl_registry *r = wl_display_get_registry(dpy); wl_registry_add_listener(r, &rl, NULL); wl_display_roundtrip(dpy);
    if (!fi) { fprintf(stderr, "no fake_input\n"); return 2; }
    org_kde_kwin_fake_input_authenticate(fi, "capture helper", "tests"); flush();
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "move")) { mv(atof(argv[i+1]), atof(argv[i+2])); i += 2; }
        else if (!strcmp(argv[i], "click")) { btn(1); btn(0); }
        else if (!strcmp(argv[i], "rclick")) { bcode = 0x111; btn(1); btn(0); bcode = 0x110; }
        else if (!strcmp(argv[i], "press")) btn(1);
        else if (!strcmp(argv[i], "release")) btn(0);
        else if (!strcmp(argv[i], "drag")) { double x1 = atof(argv[i+1]), y1 = atof(argv[i+2]), x2 = atof(argv[i+3]), y2 = atof(argv[i+4]); i += 4;
            mv(x1, y1); btn(1); for (int k = 1; k <= 20; k++) mv(x1 + (x2 - x1) * k / 20, y1 + (y2 - y1) * k / 20); btn(0); }
        else if (!strcmp(argv[i], "type")) { for (const char *c = argv[i+1]; *c; c++) { org_kde_kwin_fake_input_keyboard_keysym(fi, (unsigned char)*c, 1); flush(); usleep(30000); org_kde_kwin_fake_input_keyboard_keysym(fi, (unsigned char)*c, 0); flush(); usleep(30000); } i++; }
        else if (!strcmp(argv[i], "key")) { int k = atoi(argv[i+1]); org_kde_kwin_fake_input_keyboard_key(fi, k, 1); flush(); usleep(40000); org_kde_kwin_fake_input_keyboard_key(fi, k, 0); flush(); usleep(40000); i++; }
        else if (!strcmp(argv[i], "keydown")) { org_kde_kwin_fake_input_keyboard_keysym(fi, strtoul(argv[i+1], 0, 0), 1); flush(); usleep(40000); i++; }
        else if (!strcmp(argv[i], "keyup")) { org_kde_kwin_fake_input_keyboard_keysym(fi, strtoul(argv[i+1], 0, 0), 0); flush(); usleep(40000); i++; }
        else if (!strcmp(argv[i], "scroll")) { int n = atoi(argv[i+1]); i++; for (int k = 0; k < abs(n); k++) { org_kde_kwin_fake_input_axis(fi, 0, wl_fixed_from_double(n > 0 ? 15 : -15)); flush(); usleep(60000); } }
        else if (!strcmp(argv[i], "sleep")) { usleep(atoi(argv[i+1]) * 1000); i++; }
    }
    return 0;
}
