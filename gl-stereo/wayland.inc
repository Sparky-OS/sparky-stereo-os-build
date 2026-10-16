/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Native Wayland windows with two views through an EGL that has none, such
 * as NVIDIA's (its window surfaces take no second colour buffer). A program
 * asks for two views with EGL_EXT_multiview_window; the layer offers that
 * extension when the compositor's kde_stereo_content_v1 is at version 2,
 * gives the window a buffer twice its width, draws each view into its half
 * through the quad-buffer path and declares the surface full side by side.
 * From version 2 the compositor takes such a surface's size as one view, so
 * the program keeps its own viewport and fractional scale. Desktop OpenGL
 * names the views GL_BACK_LEFT and GL_BACK_RIGHT; OpenGL ES names them
 * through GL_EXT_multiview_draw_buffers, GL_BACK being the first, and the
 * layer offers that extension on such contexts. */
#include <wayland-client.h>
#include <wayland-egl-backend.h>

#ifndef EGL_MULTIVIEW_VIEW_COUNT_EXT
#define EGL_MULTIVIEW_VIEW_COUNT_EXT 0x3134
#endif
#ifndef EGL_PLATFORM_WAYLAND_KHR
#define EGL_PLATFORM_WAYLAND_KHR 0x31D8
#endif
#define STEREO_CONTENT_SIDE_BY_SIDE_FULL 3

static const struct wl_interface stereo_content_interface;
static const struct wl_interface *stereo_manager_types[] = {
    NULL, NULL, &stereo_content_interface, &wl_surface_interface,
};
static const struct wl_message stereo_manager_requests[] = {
    { "destroy", "", NULL },
    { "create", "no", stereo_manager_types + 2 },
};
static const struct wl_interface stereo_manager_interface = {
    "kde_stereo_content_manager_v1", 2, 2, stereo_manager_requests, 0, NULL,
};
static const struct wl_message stereo_content_requests[] = {
    { "destroy", "", NULL },
    { "set_content", "u", NULL },
};
static const struct wl_interface stereo_content_interface = {
    "kde_stereo_content_v1", 2, 2, stereo_content_requests, 0, NULL,
};

typedef struct wayland_display {
    EGLDisplay egl;
    struct wl_display *wl;
    struct wl_proxy *manager;
    char *extensions;
    struct wayland_display *next;
} WaylandDisplay;
static WaylandDisplay *wayland_displays;
static void (*r_wl_egl_window_resize)(struct wl_egl_window *, int, int, int, int);

static void registry_global(void *data, struct wl_registry *registry, uint32_t name,
                            const char *interface, uint32_t version)
{
    WaylandDisplay *p = data;
    if (!strcmp(interface, stereo_manager_interface.name) && version >= 2 && !p->manager)
        p->manager = wl_registry_bind(registry, name, &stereo_manager_interface, 2);
}
static void registry_remove(void *data, struct wl_registry *registry, uint32_t name)
{
    (void)data; (void)registry; (void)name;
}
static const struct wl_registry_listener registry_listener = { registry_global, registry_remove };

static int is_wayland_display(void *native)
{
    /* A wl_display starts with its interface pointer, as Mesa's EGL checks. */
    return native && *(const struct wl_interface **)native == &wl_display_interface;
}
static WaylandDisplay *wayland_display(EGLDisplay display)
{
    for (WaylandDisplay *p = wayland_displays; p; p = p->next)
        if (p->egl == display) return p;
    return NULL;
}
static void remember_wayland_display(EGLDisplay egl, struct wl_display *wl)
{
    if (!config.enabled || !wl || egl == EGL_NO_DISPLAY) return;
    pthread_mutex_lock(&state_lock);
    if (!wayland_display(egl)) {
        WaylandDisplay *p = calloc(1, sizeof(*p));
        if (!p) abort();
        p->egl = egl; p->wl = wl;
        struct wl_event_queue *queue = wl_display_create_queue(wl);
        struct wl_display *wrapper = queue ? wl_proxy_create_wrapper(wl) : NULL;
        if (wrapper) {
            wl_proxy_set_queue((struct wl_proxy *)wrapper, queue);
            struct wl_registry *registry = wl_display_get_registry(wrapper);
            wl_registry_add_listener(registry, &registry_listener, p);
            wl_display_roundtrip_queue(wl, queue);
            wl_registry_destroy(registry);
            wl_proxy_wrapper_destroy(wrapper);
            if (p->manager) wl_proxy_set_queue(p->manager, NULL);
        }
        if (queue) wl_event_queue_destroy(queue);
        p->next = wayland_displays; wayland_displays = p;
    }
    pthread_mutex_unlock(&state_lock);
}
static WindowState *find_wayland_window(struct wl_egl_window *win)
{
    for (WindowState *p = windows; p; p = p->next)
        if (p->wl_window == win) return p;
    return NULL;
}
static WindowState *find_wayland_surface(EGLSurface surface)
{
    for (WindowState *p = windows; p; p = p->next)
        if (p->wl_window && p->egl_surface == surface) return p;
    return NULL;
}
/* Toolkits often load libwayland-egl themselves, outside the global scope. */
static void *wayland_egl_symbol(const char *name)
{
    void *symbol = lookup_symbol(RTLD_NEXT, name);
    if (!symbol) {
        void *handle = dlopen("libwayland-egl.so.1", RTLD_NOW | RTLD_LOCAL);
        if (handle) symbol = lookup_symbol(handle, name);
    }
    return symbol;
}
static void native_resize(struct wl_egl_window *win, int width, int height, int dx, int dy)
{
    if (!r_wl_egl_window_resize) r_wl_egl_window_resize = wayland_egl_symbol("wl_egl_window_resize");
    if (r_wl_egl_window_resize) r_wl_egl_window_resize(win, width, height, dx, dy);
}
/* The layer provides the two views when the compositor sizes declared
 * surfaces and the EGL has no views of its own. */
static int wayland_views(WaylandDisplay *p)
{
    if (!p || !p->manager) return 0;
    native_query++;
    const char *native = r_eglQueryString(p->egl, EGL_EXTENSIONS);
    native_query--;
    return !native || !strstr(native, "EGL_EXT_multiview_window");
}
static const char *wayland_extensions(EGLDisplay display, const char *native)
{
    WaylandDisplay *p = wayland_display(display);
    if (!native || !wayland_views(p)) return native;
    pthread_mutex_lock(&state_lock);
    if (!p->extensions) {
        size_t len = strlen(native);
        p->extensions = malloc(len + sizeof(" EGL_EXT_multiview_window"));
        if (p->extensions) { memcpy(p->extensions, native, len); strcpy(p->extensions + len, " EGL_EXT_multiview_window"); }
    }
    pthread_mutex_unlock(&state_lock);
    return p->extensions ? p->extensions : native;
}
/* Returns the attribute list without EGL_MULTIVIEW_VIEW_COUNT_EXT and the
 * number of views asked for (1 when absent). The list is malloc'd. */
static EGLAttrib *strip_views(const EGLAttrib *attrs, int *views)
{
    size_t n = 0;
    *views = 1;
    if (attrs) while (attrs[n] != EGL_NONE) n += 2;
    EGLAttrib *out = malloc((n + 1) * sizeof(*out));
    if (!out) return NULL;
    size_t k = 0;
    for (size_t i = 0; i < n; i += 2) {
        if (attrs[i] == EGL_MULTIVIEW_VIEW_COUNT_EXT) { *views = (int)attrs[i + 1]; continue; }
        out[k++] = attrs[i]; out[k++] = attrs[i + 1];
    }
    out[k] = EGL_NONE;
    return out;
}
typedef EGLSurface (*CreateSurface)(EGLDisplay, EGLConfig, void *, const EGLAttrib *);
static EGLSurface wayland_window_surface(EGLDisplay display, EGLConfig cfg, struct wl_egl_window *win,
                                         const EGLAttrib *attrs, CreateSurface create, int *handled)
{
    *handled = 0;
    WaylandDisplay *p = wayland_display(display);
    if (!win || !wayland_views(p)) return EGL_NO_SURFACE;
    int views;
    EGLAttrib *stripped = strip_views(attrs, &views);
    if (!stripped || views != 2) { free(stripped); return EGL_NO_SURFACE; }
    *handled = 1;
    int width = win->width, height = win->height;
    native_resize(win, 2 * width, height, 0, 0);
    native_query++;
    EGLSurface result = create(display, cfg, win, stripped);
    native_query--;
    free(stripped);
    if (result == EGL_NO_SURFACE) { native_resize(win, width, height, 0, 0); return result; }
    pthread_mutex_lock(&state_lock);
    WindowState *w = calloc(1, sizeof(*w));
    if (w) {
        w->wl_window = win; w->egl_surface = result;
        w->width = width; w->height = height;
        w->active = 1; w->compositor_sizes = 1; w->doubled = 1;
        w->wl_declaration = wl_proxy_marshal_flags(p->manager, 1, &stereo_content_interface,
                                                   wl_proxy_get_version(p->manager), 0, NULL, win->surface);
        if (w->wl_declaration)
            wl_proxy_marshal_flags(w->wl_declaration, 1, NULL, wl_proxy_get_version(w->wl_declaration), 0,
                                   STEREO_CONTENT_SIDE_BY_SIDE_FULL);
        w->next = windows; windows = w;
    }
    pthread_mutex_unlock(&state_lock);
    if (getenv("GL_STEREO_DEBUG")) fprintf(stderr,"wayland two-view surface %p window %dx%d buffer %dx%d\n",(void*)result,width,height,2*width,height);
    return result;
}
static void forget_wayland_window(WindowState *w, int restore)
{
    WindowState **p = &windows;
    while (*p && *p != w) p = &(*p)->next;
    if (!*p) return;
    *p = w->next;
    for (ContextState *c = contexts; c; c = c->next) if (c->window == w) c->window = NULL;
    if (w->wl_declaration)
        wl_proxy_marshal_flags(w->wl_declaration, 0, NULL, wl_proxy_get_version(w->wl_declaration),
                               WL_MARSHAL_FLAG_DESTROY);
    if (restore) native_resize(w->wl_window, w->width, w->height, 0, 0);
    free(w);
}
static void bind_wayland_context(WindowState *w, EGLContext context, int gles)
{
    pthread_mutex_lock(&state_lock);
    ContextState *p;
    for (p = contexts; p && p->context != (GLXContext)context; p = p->next) {}
    if (!p) {
        p = calloc(1, sizeof(*p));
        if (!p) abort();
        p->context = (GLXContext)context; p->next = contexts; contexts = p;
    }
    if (!p->quad) { p->quad = 1; p->draw_buffer = GL_BACK; p->read_buffer = GL_BACK_LEFT; }
    p->egl = 1; p->gles = gles; p->window = w;
    current = p;
    pthread_mutex_unlock(&state_lock);
}

#pragma GCC visibility push(default)
void wl_egl_window_resize(struct wl_egl_window *win, int width, int height, int dx, int dy)
{
    API();
    pthread_mutex_lock(&state_lock);
    WindowState *w = config.enabled ? find_wayland_window(win) : NULL;
    if (w) { w->width = width; w->height = height; }
    pthread_mutex_unlock(&state_lock);
    native_resize(win, w ? 2 * width : width, height, dx, dy);
}
void wl_egl_window_get_attached_size(struct wl_egl_window *win, int *width, int *height)
{
    API();
    static void (*real)(struct wl_egl_window *, int *, int *);
    if (!real) real = wayland_egl_symbol("wl_egl_window_get_attached_size");
    if (real) real(win, width, height);
    pthread_mutex_lock(&state_lock);
    WindowState *w = config.enabled ? find_wayland_window(win) : NULL;
    if (w && width) *width /= 2;
    pthread_mutex_unlock(&state_lock);
}
void wl_egl_window_destroy(struct wl_egl_window *win)
{
    API();
    static void (*real)(struct wl_egl_window *);
    if (!real) real = wayland_egl_symbol("wl_egl_window_destroy");
    pthread_mutex_lock(&state_lock);
    WindowState *w = config.enabled ? find_wayland_window(win) : NULL;
    if (w) forget_wayland_window(w, 0);
    pthread_mutex_unlock(&state_lock);
    if (real) real(win);
}
#pragma GCC visibility pop
