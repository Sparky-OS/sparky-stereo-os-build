// SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
// SPDX-License-Identifier: MIT
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/extensions/Xcomposite.h>
#include <X11/extensions/Xdamage.h>
#include <stereo-declare.h>
#include <signal.h>
#include <poll.h>
#include <locale.h>
#include <libintl.h>
#define _(text) gettext(text)
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static volatile sig_atomic_t stopped;
static int failed;
static int xerror(Display *display, XErrorEvent *event)
{
    char message[256];
    XGetErrorText(display, event->error_code, message, sizeof(message));
    fprintf(stderr, "X11: %s (request %u.%u)\n", message, event->request_code, event->minor_code);
    failed = 1;
    stopped = 1;
    return failed ? 1 : 0;
}
static void stop(int signal_number) { (void)signal_number; stopped = 1; }

int main(int argc, char **argv)
{
    setlocale(LC_ALL, "");
    bindtextdomain("wine-sbs-view", "/usr/share/locale");
    bind_textdomain_codeset("wine-sbs-view", "UTF-8");
    textdomain("wine-sbs-view");
    if (argc != 2) {
        fprintf(stderr, _("Usage: wine-sbs-view X11_IMAGE_WINDOW_ID\nSelect a full side by side image window with the left eye first and no controls.\n"));
        return 2;
    }
    char *end;
    const Window source = strtoul(argv[1], &end, 0);
    if (*end || !source) return 2;
    Display *display = XOpenDisplay(NULL);
    if (!display) return 2;
    XSetErrorHandler(xerror);
    int damage_event, error, composite_event;
    if (stereo_supported_x11(display) < 6 || !XCompositeQueryExtension(display, &composite_event, &error)
        || !XDamageQueryExtension(display, &damage_event, &error)) {
        fprintf(stderr, _("Stereo declaration version 6, Composite and Damage are required.\n"));
        XCloseDisplay(display);
        return 2;
    }
    XWindowAttributes attributes;
    if (!XGetWindowAttributes(display, source, &attributes) || attributes.width % 2
        || attributes.width < 2 || attributes.width > 65534 || attributes.height < 1 || attributes.height > 32767 || attributes.map_state != IsViewable || attributes.depth != DefaultDepth(display, DefaultScreen(display))) {
        fprintf(stderr, _("Select a visible image window with even width and the display depth.\n"));
        XCloseDisplay(display);
        return 2;
    }
    XCompositeRedirectWindow(display, source, CompositeRedirectAutomatic);
    XSelectInput(display, source, StructureNotifyMask);
    const Damage damage = XDamageCreate(display, source, XDamageReportNonEmpty);
    Pixmap pixmap = XCompositeNameWindowPixmap(display, source);
    const Window window = XCreateSimpleWindow(display, DefaultRootWindow(display), 800, 200,
                                               attributes.width / 2, attributes.height, 0, 0, 0);
    const char *title = _("Stereo SBS image");
    Xutf8SetWMProperties(display, window, title, title, NULL, 0, NULL, NULL, NULL);
    XChangeProperty(display, window, XInternAtom(display, "_NET_WM_NAME", False),
                    XInternAtom(display, "UTF8_STRING", False), 8, PropModeReplace,
                    (const unsigned char *)title, strlen(title));
    XSelectInput(display, window, ExposureMask | StructureNotifyMask);
    Atom close = XInternAtom(display, "WM_DELETE_WINDOW", False);
    XSetWMProtocols(display, window, &close, 1);
    if (stereo_declare_x11(display, window, STEREO_SBS_FULL, STEREO_CLASS_VIDEO, STEREO_VIDEO_LEGACY)
        || stereo_declare_x11_one_view_size(display, window, attributes.width / 2, attributes.height)) return 2;
    GC gc = XCreateGC(display, window, 0, NULL);
    XSetGraphicsExposures(display, gc, False);
    XMapWindow(display, window);
    XFlush(display);
    printf("source=0x%lx view=0x%lx packed=%dx%d\n", source, window, attributes.width, attributes.height);
    fflush(stdout);
    signal(SIGTERM, stop);
    signal(SIGINT, stop);
    while (!stopped) {
        if (!XPending(display)) {
            struct pollfd descriptor = {ConnectionNumber(display), POLLIN, 0};
            if (poll(&descriptor, 1, 250) <= 0) continue;
        }
        XEvent event;
        XNextEvent(display, &event);
        if (event.type == ClientMessage && (Atom)event.xclient.data.l[0] == close) break;
        if ((event.type == DestroyNotify && event.xdestroywindow.window == source)
            || (event.type == UnmapNotify && event.xunmap.window == source)) break;
        if (event.type == ConfigureNotify && event.xconfigure.window == source) {
            if (event.xconfigure.width % 2 || event.xconfigure.width < 2) break;
            if (event.xconfigure.width == attributes.width && event.xconfigure.height == attributes.height) continue;
            attributes.width = event.xconfigure.width;
            attributes.height = event.xconfigure.height;
            XResizeWindow(display, window, attributes.width / 2, attributes.height);
            stereo_declare_x11_one_view_size(display, window, attributes.width / 2, attributes.height);
        }
        if (event.type == Expose || event.type == damage_event + XDamageNotify || event.type == ConfigureNotify) {
            XDamageSubtract(display, damage, None, None);
            // A graphics buffer can be replaced without changing the window size.
            XFreePixmap(display, pixmap);
            pixmap = XCompositeNameWindowPixmap(display, source);
            XCopyArea(display, pixmap, window, gc, 0, 0, attributes.width, attributes.height, 0, 0);
            XFlush(display);
        }
    }
    // Closing this connection releases the redirect, damage, pixmap and declared window,
    // including when the source has already gone away.
    (void)damage;
    XCloseDisplay(display);
    return failed ? 1 : 0;
}
