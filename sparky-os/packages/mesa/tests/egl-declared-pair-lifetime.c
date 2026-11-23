/* A declared Wayland EGL surface holding two views, through every lifecycle order a client may take (row 830).
 *
 * egl-declared-pair-lifetime ROUTE ORDER REPEATS
 *   ROUTE  packed     the program draws its two views into one buffer twice a view wide and declares the surface
 *                     full side by side with libstereo-declare (OBS's preview, a player's video surface);
 *          multiview  an EGL_EXT_multiview_window surface of two views, which Mesa declares at the first right-eye
 *                     draw (Qt's stereo window);
 *          mono       an ordinary EGL window, nothing declared (the 2D control).
 *   ORDER  declared   the EGL surface goes, then the wl_surface while it is still declared (OBS before its repair:
 *                     the display is destroyed on visibleChanged(false), Qt then drops the window's surface);
 *          surface-first  the wl_surface goes while the EGL surface still draws on it and it is declared, the EGL
 *                     surface after (Qt destroys a hidden window's surface before the program releases its EGL one);
 *          withdraw-first the declaration is taken back, then the EGL surface, then the wl_surface (the pack's repair);
 *          hide-show  the surface is unmapped (a null buffer) and shown again, all objects kept;
 *          resize     the window is resized every frame while declared;
 *          redeclare  the declaration is taken back and made again on the same surface every frame;
 *          late-release  everything is destroyed right after a swap, before the compositor releases the buffers.
 *   REPEATS how many times a child surface is made, drawn and taken down; between rounds the heap is exercised so
 *           that glibc checks its chunks (realloc and free of many sizes, as a program's own allocations do).
 * THREAD=1 keeps a second declared surface drawing on a thread of its own the whole time, as OBS's graphics thread
 * keeps its other views drawing while the interface thread takes one down.
 * The child is a desynchronized sub-surface of an ordinary xdg toplevel drawn with wl_shm, as Qt's native child window.
 * Exit 0 only when every round completed; glibc or a sanitizer ends the process otherwise.
 */
#define _GNU_SOURCE
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GL/gl.h>
#include <errno.h>
#include <malloc.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>
#include <wayland-egl.h>
#include <stereo-declare.h>
#include "xdg-shell-client-protocol.h"

#ifndef EGL_MULTIVIEW_VIEW_COUNT_EXT
#define EGL_MULTIVIEW_VIEW_COUNT_EXT 0x3134
#endif

enum route { PACKED, MULTIVIEW, MONO };
enum order { DECLARED, SURFACE_FIRST, WITHDRAW_FIRST, HIDE_SHOW, RESIZE, REDECLARE, LATE_RELEASE, NEVER_WITHDRAWN, CURRENT_DESTROY };

static struct wl_display *connection;
static struct wl_compositor *compositor;
static struct wl_subcompositor *subcompositor;
static struct wl_shm *shm;
static struct xdg_wm_base *shell;
static EGLDisplay display;
static EGLConfig config;
static enum route route;
static enum order order;
static const int view_w = 320, view_h = 240;
static atomic_int stop_thread;

static void require(int ok, const char *what)
{
    if (!ok) {
        fprintf(stderr, "FAIL %s (egl 0x%x, gl 0x%x, errno %d)\n", what, eglGetError(), glGetError(), errno);
        exit(1);
    }
}

static void global(void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version)
{
    (void)data;
    if (!strcmp(interface, wl_compositor_interface.name))
        compositor = wl_registry_bind(registry, name, &wl_compositor_interface, version < 4 ? version : 4);
    else if (!strcmp(interface, wl_subcompositor_interface.name))
        subcompositor = wl_registry_bind(registry, name, &wl_subcompositor_interface, 1);
    else if (!strcmp(interface, wl_shm_interface.name))
        shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
    else if (!strcmp(interface, xdg_wm_base_interface.name))
        shell = wl_registry_bind(registry, name, &xdg_wm_base_interface, 1);
}
static void global_remove(void *data, struct wl_registry *registry, uint32_t name)
{ (void)data; (void)registry; (void)name; }
static const struct wl_registry_listener registry_listener = { global, global_remove };

static void ping(void *data, struct xdg_wm_base *base, uint32_t serial)
{ (void)data; xdg_wm_base_pong(base, serial); }
static const struct xdg_wm_base_listener shell_listener = { ping };

static int configured;
static void surface_configure(void *data, struct xdg_surface *surface, uint32_t serial)
{ (void)data; xdg_surface_ack_configure(surface, serial); configured = 1; }
static const struct xdg_surface_listener surface_listener = { surface_configure };
static void toplevel_configure(void *data, struct xdg_toplevel *top, int32_t w, int32_t h, struct wl_array *states)
{ (void)data; (void)top; (void)w; (void)h; (void)states; }
static void toplevel_close(void *data, struct xdg_toplevel *top) { (void)data; (void)top; }
static const struct xdg_toplevel_listener toplevel_listener = { toplevel_configure, toplevel_close };

/* The toplevel the child lives in, drawn once with wl_shm in a plain grey. */
static struct wl_surface *parent;
static void make_parent(void)
{
    const int w = 800, h = 600, stride = w * 4;
    parent = wl_compositor_create_surface(compositor);
    struct xdg_surface *role = xdg_wm_base_get_xdg_surface(shell, parent);
    xdg_surface_add_listener(role, &surface_listener, NULL);
    struct xdg_toplevel *top = xdg_surface_get_toplevel(role);
    xdg_toplevel_add_listener(top, &toplevel_listener, NULL);
    xdg_toplevel_set_title(top, "declared pair lifetime");
    xdg_toplevel_set_app_id(top, "org.sparkyos.DeclaredPairLifetime");
    wl_surface_commit(parent);
    while (!configured)
        require(wl_display_dispatch(connection) >= 0, "configure");
    int fd = memfd_create("parent", MFD_CLOEXEC);
    require(fd >= 0 && ftruncate(fd, (off_t)stride * h) == 0, "shm file");
    uint32_t *pixels = mmap(NULL, (size_t)stride * h, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    require(pixels != MAP_FAILED, "shm map");
    for (int i = 0; i < w * h; i++)
        pixels[i] = 0xff404040;
    struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, stride * h);
    struct wl_buffer *buffer = wl_shm_pool_create_buffer(pool, 0, w, h, stride, WL_SHM_FORMAT_XRGB8888);
    wl_shm_pool_destroy(pool);
    close(fd);
    wl_surface_attach(parent, buffer, 0, 0);
    wl_surface_damage_buffer(parent, 0, 0, w, h);
    wl_surface_commit(parent);
    require(wl_display_roundtrip(connection) >= 0, "parent roundtrip");
}

struct child {
    struct wl_surface *surface;
    struct wl_subsurface *sub;
    struct wl_egl_window *native;
    EGLSurface egl;
    int declared;
    struct wl_surface *gone; /* the destroyed surface a late withdrawal names, as a program holding its pointer does */
};

static int buffer_width(int w) { return route == PACKED ? 2 * w : w; }

static void declare(struct child *c)
{
    if (route != PACKED)
        return;
    require(stereo_declare_wayland_format(c->surface, STEREO_SBS_FULL) == 0, "declare");
    c->declared = 1;
}

static void withdraw(struct child *c)
{
    if (route == PACKED && c->declared)
        require(stereo_remove_wayland(c->surface ? c->surface : c->gone) == 0, "withdraw");
    c->declared = 0;
}

static void make_child(struct child *c, EGLContext context, int x, int y)
{
    memset(c, 0, sizeof(*c));
    c->surface = wl_compositor_create_surface(compositor);
    require(c->surface != NULL, "child surface");
    struct wl_region *none = wl_compositor_create_region(compositor);
    wl_surface_set_input_region(c->surface, none);
    wl_region_destroy(none);
    c->sub = wl_subcompositor_get_subsurface(subcompositor, c->surface, parent);
    wl_subsurface_set_position(c->sub, x, y);
    wl_subsurface_set_desync(c->sub);
    wl_surface_commit(parent);
    declare(c);
    c->native = wl_egl_window_create(c->surface, buffer_width(view_w), view_h);
    require(c->native != NULL, "native window");
    const EGLint two[] = { EGL_MULTIVIEW_VIEW_COUNT_EXT, 2, EGL_NONE };
    c->egl = eglCreateWindowSurface(display, config, (EGLNativeWindowType)c->native, route == MULTIVIEW ? two : NULL);
    require(c->egl != EGL_NO_SURFACE, "EGL window surface");
    require(eglMakeCurrent(display, c->egl, c->egl, context), "make current");
    require(eglSwapInterval(display, 0), "swap interval");
}

/* Left view red, right view blue, a frame counter in green so that no two frames are alike. */
static void draw(struct child *c, int frame, int w, int h)
{
    const float g = (float)(frame % 32) / 64.0f;
    glDisable(GL_SCISSOR_TEST);
    if (route == MULTIVIEW) {
        glViewport(0, 0, w, h);
        glDrawBuffer(GL_BACK_LEFT);
        glClearColor(1, g, 0, 1);
        glClear(GL_COLOR_BUFFER_BIT);
        glDrawBuffer(GL_BACK_RIGHT);
        glClearColor(0, g, 1, 1);
        glClear(GL_COLOR_BUFFER_BIT);
        glDrawBuffer(GL_BACK);
    } else if (route == PACKED) {
        glViewport(0, 0, 2 * w, h);
        glEnable(GL_SCISSOR_TEST);
        glScissor(0, 0, w, h);
        glClearColor(1, g, 0, 1);
        glClear(GL_COLOR_BUFFER_BIT);
        glScissor(w, 0, w, h);
        glClearColor(0, g, 1, 1);
        glClear(GL_COLOR_BUFFER_BIT);
        glDisable(GL_SCISSOR_TEST);
    } else {
        glViewport(0, 0, w, h);
        glClearColor(1, g, 0, 1);
        glClear(GL_COLOR_BUFFER_BIT);
    }
    require(glGetError() == GL_NO_ERROR, "draw");
    require(eglSwapBuffers(display, c->egl), "swap");
}

static void destroy_egl(struct child *c)
{
    require(eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT), "release current");
    require(eglDestroySurface(display, c->egl), "destroy EGL surface");
    wl_egl_window_destroy(c->native);
    c->egl = EGL_NO_SURFACE;
    c->native = NULL;
}

static void destroy_surface(struct child *c)
{
    wl_subsurface_destroy(c->sub);
    wl_surface_destroy(c->surface);
    wl_surface_commit(parent);
    c->gone = c->surface;
    c->sub = NULL;
    c->surface = NULL;
}

/* A program's own allocations between rounds, so that glibc walks and checks neighbouring chunks. */
static void exercise_heap(unsigned seed)
{
    void *blocks[256] = { 0 };
    for (int i = 0; i < 4096; i++) {
        seed = seed * 1103515245u + 12345u;
        const int slot = (seed >> 8) & 255;
        const size_t size = 8 + ((seed >> 16) % 4096);
        void *grown = realloc(blocks[slot], size);
        require(grown != NULL, "realloc");
        memset(grown, (int)(seed & 255), size);
        blocks[slot] = grown;
        if ((seed & 7) == 0) {
            free(blocks[slot]);
            blocks[slot] = NULL;
        }
    }
    for (int i = 0; i < 256; i++)
        free(blocks[i]);
}

static void round_trip(void) { require(wl_display_roundtrip(connection) >= 0, "roundtrip"); }

static EGLContext make_context(void)
{
    EGLContext context = eglCreateContext(display, config, EGL_NO_CONTEXT, NULL);
    require(context != EGL_NO_CONTEXT, "context");
    return context;
}

/* THREAD=1: another declared surface keeps drawing on its own thread and context. */
static pthread_mutex_t wl_lock = PTHREAD_MUTEX_INITIALIZER;
static struct child steady;
static void *steady_thread(void *arg)
{
    EGLContext context = arg;
    require(eglMakeCurrent(display, steady.egl, steady.egl, context), "steady current");
    for (int frame = 0; !atomic_load(&stop_thread); frame++)
        draw(&steady, frame, view_w, view_h);
    require(eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT), "steady release");
    return NULL;
}

int main(int argc, char **argv)
{
    require(argc == 4, "usage: egl-declared-pair-lifetime packed|multiview|mono ORDER REPEATS");
    route = !strcmp(argv[1], "packed") ? PACKED : !strcmp(argv[1], "multiview") ? MULTIVIEW : MONO;
    require(route != MONO || !strcmp(argv[1], "mono"), "route");
    static const char *orders[] = { "declared", "surface-first", "withdraw-first", "hide-show", "resize",
                                    "redeclare", "late-release", "never-withdrawn", "current-destroy" };
    order = (enum order)-1;
    for (unsigned i = 0; i < sizeof(orders) / sizeof(orders[0]); i++)
        if (!strcmp(argv[2], orders[i]))
            order = (enum order)i;
    require((int)order >= 0, "order");
    const int repeats = atoi(argv[3]);
    require(repeats > 0, "repeats");
    const int threaded = getenv("THREAD") && !strcmp(getenv("THREAD"), "1");
    (void)wl_lock;

    connection = wl_display_connect(NULL);
    require(connection != NULL, "Wayland display");
    struct wl_registry *registry = wl_display_get_registry(connection);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    if (route == PACKED)
        require(stereo_declare_wayland_init(connection, NULL) == 0, "stereo_declare_wayland_init");
    round_trip();
    round_trip();
    require(compositor && subcompositor && shm && shell, "globals");
    xdg_wm_base_add_listener(shell, &shell_listener, NULL);
    if (route == PACKED)
        require(stereo_supported_wayland() != 0, "compositor offers the declaration");

    display = eglGetPlatformDisplay(EGL_PLATFORM_WAYLAND_KHR, connection, NULL);
    require(display != EGL_NO_DISPLAY && eglInitialize(display, NULL, NULL), "EGL display");
    require(eglBindAPI(EGL_OPENGL_API), "OpenGL API");
    const EGLint attrs[] = { EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8,
                             EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT, EGL_NONE };
    EGLint count = 0;
    require(eglChooseConfig(display, attrs, &config, 1, &count) && count == 1, "config");
    printf("VENDOR %s\nRENDER route=%s order=%s repeats=%d thread=%d\n", eglQueryString(display, EGL_VENDOR),
           argv[1], argv[2], repeats, threaded);
    make_parent();
    EGLContext context = make_context();
    pthread_t thread;
    if (threaded) {
        EGLContext second = make_context();
        make_child(&steady, second, 420, 300);
        require(eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT), "hand over");
        require(pthread_create(&thread, NULL, steady_thread, second) == 0, "thread");
    }
    const GLubyte *renderer = NULL;
    for (int r = 0; r < repeats; r++) {
        struct child c;
        make_child(&c, context, 40, 40);
        if (!renderer) {
            renderer = glGetString(GL_RENDERER);
            printf("GL_RENDERER %s\n", renderer);
        }
        const int frames = order == RESIZE || order == REDECLARE ? 12 : 4;
        for (int f = 0; f < frames; f++) {
            int w = view_w, h = view_h;
            if (order == RESIZE) {
                w = view_w - 8 * (f % 5);
                h = view_h - 6 * (f % 3);
                wl_egl_window_resize(c.native, buffer_width(w), h, 0, 0);
            }
            if (order == REDECLARE && f > 0) {
                withdraw(&c);
                declare(&c);
            }
            draw(&c, f, w, h);
            if (order == HIDE_SHOW && f == 1) {
                wl_surface_attach(c.surface, NULL, 0, 0);
                wl_surface_commit(c.surface);
                round_trip();
            }
            if (order != LATE_RELEASE)
                round_trip();
        }
        switch (order) {
        case DECLARED:
            destroy_egl(&c);
            destroy_surface(&c);
            round_trip();
            withdraw(&c);
            break;
        case CURRENT_DESTROY:
            require(eglDestroySurface(display, c.egl), "destroy current EGL surface");
            wl_egl_window_destroy(c.native);
            destroy_surface(&c);
            round_trip();
            require(eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT), "deferred destroy");
            withdraw(&c);
            break;
        case NEVER_WITHDRAWN:
            destroy_egl(&c);
            destroy_surface(&c);
            break;
        case SURFACE_FIRST:
            destroy_surface(&c);
            round_trip();
            destroy_egl(&c);
            round_trip();
            withdraw(&c);
            break;
        case WITHDRAW_FIRST:
            withdraw(&c);
            destroy_egl(&c);
            destroy_surface(&c);
            break;
        case LATE_RELEASE:
            destroy_egl(&c);
            withdraw(&c);
            destroy_surface(&c);
            break;
        default:
            withdraw(&c);
            destroy_egl(&c);
            destroy_surface(&c);
            break;
        }
        round_trip();
        exercise_heap((unsigned)r * 2654435761u + 1);
        printf("ROUND %d done\n", r);
        fflush(stdout);
    }
    if (threaded) {
        atomic_store(&stop_thread, 1);
        pthread_join(thread, NULL);
        withdraw(&steady);
        destroy_egl(&steady);
        destroy_surface(&steady);
    }
    exercise_heap(7);
    malloc_trim(0);
    printf("DONE rounds=%d\n", repeats);
    return 0;
}
