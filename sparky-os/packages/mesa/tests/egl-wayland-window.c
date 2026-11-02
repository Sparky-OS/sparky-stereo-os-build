/* SPDX-License-Identifier: MIT */
/* Driver-owned EGL multiview declaration probe. No stereo protocol writer. */
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GL/gl.h>
#include <wayland-client.h>
#include <wayland-egl.h>
#include "xdg-shell-client-protocol.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static struct wl_display *connection;
static struct wl_compositor *compositor;
static struct xdg_wm_base *shell;
static EGLDisplay display;
static EGLConfig config;
static EGLContext context;
static const char *output;
static int views, both;
struct window {
    struct wl_surface *surface;
    struct xdg_surface *role;
    struct xdg_toplevel *toplevel;
    struct wl_egl_window *native;
    EGLSurface egl;
    int configured;
};
static void require(int ok, const char *what)
{
    if (!ok) {
        fprintf(stderr, "FAIL %s EGL=%#x GL=%#x\n", what,
                eglGetError(), glGetError());
        exit(1);
    }
}
static void ping(void *data, struct xdg_wm_base *base, uint32_t serial)
{ (void)data; xdg_wm_base_pong(base, serial); }
static const struct xdg_wm_base_listener shell_listener = { .ping = ping };
static void global(void *data, struct wl_registry *registry, uint32_t name,
                   const char *interface, uint32_t version)
{
    (void)data;
    if (!strcmp(interface, "wl_compositor"))
        compositor = wl_registry_bind(registry, name, &wl_compositor_interface,
                                      version < 4 ? version : 4);
    else if (!strcmp(interface, "xdg_wm_base")) {
        shell = wl_registry_bind(registry, name, &xdg_wm_base_interface, 1);
        xdg_wm_base_add_listener(shell, &shell_listener, NULL);
    }
}
static void global_remove(void *data, struct wl_registry *registry, uint32_t name)
{ (void)data; (void)registry; (void)name; }
static const struct wl_registry_listener registry_listener = { global, global_remove };
static void configure(void *data, struct xdg_surface *surface, uint32_t serial)
{
    struct window *w = data;
    xdg_surface_ack_configure(surface, serial);
    w->configured = 1;
}
static const struct xdg_surface_listener surface_listener = { .configure = configure };
static void toplevel_configure(void *data, struct xdg_toplevel *top,
                               int32_t width, int32_t height, struct wl_array *states)
{ (void)data; (void)top; (void)width; (void)height; (void)states; }
static void toplevel_close(void *data, struct xdg_toplevel *top)
{ (void)data; (void)top; require(0, "unexpected compositor close"); }
static const struct xdg_toplevel_listener toplevel_listener = {
    .configure = toplevel_configure, .close = toplevel_close
};
static void create_window(struct window *w, int width, int height)
{
    memset(w, 0, sizeof(*w));
    w->surface = wl_compositor_create_surface(compositor);
    w->role = xdg_wm_base_get_xdg_surface(shell, w->surface);
    xdg_surface_add_listener(w->role, &surface_listener, w);
    w->toplevel = xdg_surface_get_toplevel(w->role);
    xdg_toplevel_add_listener(w->toplevel, &toplevel_listener, w);
    xdg_toplevel_set_title(w->toplevel, "EGL multiview window probe");
    xdg_toplevel_set_app_id(w->toplevel, "org.sparkyos.EglWindowProbe");
    xdg_surface_set_window_geometry(w->role, 0, 0, width, height);
    wl_surface_commit(w->surface);
    while (!w->configured)
        require(wl_display_dispatch(connection) >= 0, "initial configure");
    w->native = wl_egl_window_create(w->surface, width, height);
    require(w->native != NULL, "native window");
    const EGLint attrs[] = { EGL_MULTIVIEW_VIEW_COUNT_EXT, views, EGL_NONE };
    w->egl = eglCreateWindowSurface(display, config, (EGLNativeWindowType)w->native,
                                   views == 2 ? attrs : NULL);
    require(w->egl != EGL_NO_SURFACE, "window surface");
    require(eglMakeCurrent(display, w->egl, w->egl, context), "make current");
    GLboolean stereo = GL_FALSE;
    glGetBooleanv(GL_STEREO, &stereo);
    require(stereo == (views == 2), "stereo capability");
    printf("SURFACE id=%u views=%d stereo=%d\n",
           wl_proxy_get_id((struct wl_proxy *)w->surface), views, stereo);
}
static void destroy_window(struct window *w)
{
    require(eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT),
            "release current");
    require(eglDestroySurface(display, w->egl), "destroy EGL surface");
    wl_egl_window_destroy(w->native);
    xdg_toplevel_destroy(w->toplevel);
    xdg_surface_destroy(w->role);
    wl_surface_destroy(w->surface);
    require(wl_display_roundtrip(connection) >= 0, "destroy roundtrip");
}
static void frame(struct window *w, const char *stage, int width, int height)
{
    wl_egl_window_resize(w->native, width, height, 0, 0);
    xdg_surface_set_window_geometry(w->role, 0, 0, width, height);
    glViewport(0, 0, width, height);
    glDisable(GL_DITHER);
    glMatrixMode(GL_PROJECTION); glLoadIdentity();
    glMatrixMode(GL_MODELVIEW); glLoadIdentity();
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    size_t size = (size_t)width * height * 3;
    unsigned char *want = malloc(size), *actual = malloc(size);
    require(want && actual, "pixel arrays");
    for (int eye = 0; eye < (both ? 2 : 1); ++eye) {
        for (int y = 0; y < height; ++y)
            for (int x = 0; x < width; ++x) {
                size_t offset = ((size_t)y * width + x) * 3;
                want[offset] = x + 17; want[offset + 1] = y + 31;
                want[offset + 2] = eye ? 201 : 73;
            }
        GLenum buffer = eye ? GL_BACK_RIGHT : GL_BACK_LEFT;
        glDrawBuffer(buffer);
        glRasterPos2f(-1, -1);
        glDrawPixels(width, height, GL_RGB, GL_UNSIGNED_BYTE, want);
        glReadBuffer(buffer);
        glReadPixels(0, 0, width, height, GL_RGB, GL_UNSIGNED_BYTE, actual);
        unsigned errors = 0;
        for (size_t n = 0; n < size; n += 3)
            errors += memcmp(actual + n, want + n, 3) != 0;
        char name[1024];
        require(snprintf(name, sizeof(name), "%s/%s-eye%d.rgb", output, stage, eye)
                < (int)sizeof(name), "output path");
        FILE *file = fopen(name, "wb"); require(file != NULL, "raw output");
        require(fwrite(actual, 1, size, file) == size && fclose(file) == 0, "raw write");
        printf("RAW stage=%s eye=%d width=%d height=%d errors=%u\n",
               stage, eye, width, height, errors);
        require(errors == 0 && glGetError() == GL_NO_ERROR, "back pixels");
    }
    free(actual); free(want);
    require(eglSwapBuffers(display, w->egl), "swap");
    require(wl_display_roundtrip(connection) >= 0, "swap roundtrip");
    EGLint ew, eh;
    require(eglQuerySurface(display, w->egl, EGL_WIDTH, &ew) &&
            eglQuerySurface(display, w->egl, EGL_HEIGHT, &eh), "surface dimensions");
    require(ew == width && eh == height, "logical dimensions");
    printf("FRAME stage=%s surface=%u width=%d height=%d\n", stage,
           wl_proxy_get_id((struct wl_proxy *)w->surface), width, height);
    fflush(stdout);
    char line[32]; require(fgets(line, sizeof(line), stdin) != NULL, "capture barrier");
    require(!strcmp(line, "next\n"), "barrier command");
}
int main(int argc, char **argv)
{
    require(argc == 3, "usage: egl-wayland-window mono|left-only|stereo OUTPUT");
    require(!strcmp(argv[1], "mono") || !strcmp(argv[1], "left-only") ||
            !strcmp(argv[1], "stereo"), "mode");
    views = strcmp(argv[1], "mono") ? 2 : 1;
    both = !strcmp(argv[1], "stereo"); output = argv[2];
    connection = wl_display_connect(NULL); require(connection != NULL, "Wayland display");
    struct wl_registry *registry = wl_display_get_registry(connection);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    require(wl_display_roundtrip(connection) >= 0 && compositor && shell, "globals");
    display = eglGetPlatformDisplay(EGL_PLATFORM_WAYLAND_KHR, connection, NULL);
    require(display != EGL_NO_DISPLAY && eglInitialize(display, NULL, NULL), "EGL display");
    const char *extensions = eglQueryString(display, EGL_EXTENSIONS);
    require(extensions && strstr(extensions, "EGL_EXT_multiview_window"), "multiview extension");
    require(eglBindAPI(EGL_OPENGL_API), "OpenGL API");
    const EGLint attrs[] = { EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT, EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8, EGL_NONE };
    EGLint count;
    require(eglChooseConfig(display, attrs, &config, 1, &count) && count, "window config");
    context = eglCreateContext(display, config, EGL_NO_CONTEXT, NULL);
    require(context != EGL_NO_CONTEXT, "context");
    struct window w;
    create_window(&w, 96, 64);
    printf("PROVIDER vendor=%s renderer=%s\n", glGetString(GL_VENDOR), glGetString(GL_RENDERER));
    frame(&w, "first", 96, 64);
    frame(&w, "resize", 80, 48);
    frame(&w, "repeat", 80, 48);
    destroy_window(&w);
    create_window(&w, 96, 64);
    frame(&w, "recreated", 96, 64);
    destroy_window(&w);
    require(eglDestroyContext(display, context), "destroy context");
    require(eglTerminate(display), "terminate");
    xdg_wm_base_destroy(shell); wl_compositor_destroy(compositor);
    wl_registry_destroy(registry); wl_display_disconnect(connection);
    puts("PASS"); return 0;
}
