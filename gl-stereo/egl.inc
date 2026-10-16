/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Included with the core's private context/window state. Desktop GL on X11
 * windows, and on Wayland windows with two views (wayland.inc). */
typedef struct egl_display_state {
    EGLDisplay egl; Display *x11; struct egl_display_state *next;
} EGLDisplayState;
static EGLDisplayState *egl_displays;
static Display *egl_x11(EGLDisplay display)
{
    for (EGLDisplayState *p = egl_displays; p; p = p->next)
        if (p->egl == display) return p->x11;
    return NULL;
}
static void remember_egl_display(EGLDisplay egl, Display *x11)
{
    if (!config.enabled || !x11 || egl == EGL_NO_DISPLAY) return;
    pthread_mutex_lock(&state_lock);
    if (!egl_x11(egl)) {
        EGLDisplayState *p = calloc(1,sizeof(*p));
        if (!p) abort();
        p->egl = egl; p->x11 = x11; p->next = egl_displays; egl_displays = p;
    }
    pthread_mutex_unlock(&state_lock);
}
EGLDisplay eglGetDisplay(EGLNativeDisplayType display)
{
    API(); EGLDisplay result = r_eglGetDisplay(display);
    if (display == EGL_DEFAULT_DISPLAY) return result;
    if (is_wayland_display((void *)display)) remember_wayland_display(result, (struct wl_display *)display);
    else remember_egl_display(result, (Display *)display);
    return result;
}
static void remember_platform_display(EGLenum platform, void *display, EGLDisplay result)
{
    if (platform == EGL_PLATFORM_X11_EXT && display) remember_egl_display(result,display);
    if (platform == EGL_PLATFORM_WAYLAND_KHR && display) remember_wayland_display(result,display);
}
EGLDisplay eglGetPlatformDisplay(EGLenum platform, void *display, const EGLAttrib *attrs)
{
    API(); EGLDisplay result = r_eglGetPlatformDisplay(platform,display,attrs);
    remember_platform_display(platform,display,result);
    return result;
}
EGLDisplay eglGetPlatformDisplayEXT(EGLenum platform, void *display, const EGLint *attrs)
{
    API();
    PFNEGLGETPLATFORMDISPLAYEXTPROC get = (PFNEGLGETPLATFORMDISPLAYEXTPROC)r_eglGetProcAddress("eglGetPlatformDisplayEXT");
    if (!get) return EGL_NO_DISPLAY;
    EGLDisplay result = get(platform,display,attrs);
    remember_platform_display(platform,display,result);
    return result;
}
const char *eglQueryString(EGLDisplay display, EGLint name)
{
    API(); const char *result = r_eglQueryString(display,name);
    if (name == EGL_EXTENSIONS && !native_query && display != EGL_NO_DISPLAY) result = wayland_extensions(display,result);
    return result;
}
static void remember_egl_surface(EGLDisplay display, EGLSurface surface, Window win)
{
    pthread_mutex_lock(&state_lock);
    WindowState *w = find_window(egl_x11(display), win);
    if (w) w->egl_surface = surface;
    pthread_mutex_unlock(&state_lock);
}
static EGLint *int_attribs(const EGLAttrib *attrs)
{
    size_t n = 0;
    if (attrs) while (attrs[n] != EGL_NONE) n += 2;
    EGLint *out = malloc((n + 1) * sizeof(*out));
    if (!out) return NULL;
    for (size_t i = 0; i < n; ++i) out[i] = (EGLint)attrs[i];
    out[n] = EGL_NONE;
    return out;
}
static EGLAttrib *wide_attribs(const EGLint *attrs)
{
    size_t n = 0;
    if (attrs) while (attrs[n] != EGL_NONE) n += 2;
    EGLAttrib *out = malloc((n + 1) * sizeof(*out));
    if (!out) return NULL;
    for (size_t i = 0; i < n; ++i) out[i] = attrs[i];
    out[n] = EGL_NONE;
    return out;
}
static EGLSurface create_window_int(EGLDisplay display, EGLConfig cfg, void *win, const EGLAttrib *attrs)
{
    EGLint *list = int_attribs(attrs);
    EGLSurface result = list ? r_eglCreateWindowSurface(display,cfg,(EGLNativeWindowType)win,list) : EGL_NO_SURFACE;
    free(list); return result;
}
static EGLSurface create_platform_window(EGLDisplay display, EGLConfig cfg, void *win, const EGLAttrib *attrs)
{
    return r_eglCreatePlatformWindowSurface(display,cfg,win,attrs);
}
static EGLSurface create_platform_window_ext(EGLDisplay display, EGLConfig cfg, void *win, const EGLAttrib *attrs)
{
    PFNEGLCREATEPLATFORMWINDOWSURFACEEXTPROC create =
        (PFNEGLCREATEPLATFORMWINDOWSURFACEEXTPROC)r_eglGetProcAddress("eglCreatePlatformWindowSurfaceEXT");
    EGLint *list = int_attribs(attrs);
    EGLSurface result = create && list ? create(display,cfg,win,list) : EGL_NO_SURFACE;
    free(list); return result;
}
EGLSurface eglCreateWindowSurface(EGLDisplay display, EGLConfig cfg, EGLNativeWindowType win, const EGLint *attrs)
{
    API(); int handled = 0;
    if (wayland_display(display)) {
        EGLAttrib *wide = wide_attribs(attrs);
        EGLSurface result = wide ? wayland_window_surface(display,cfg,(struct wl_egl_window *)win,wide,create_window_int,&handled) : EGL_NO_SURFACE;
        free(wide);
        if (handled) return result;
    }
    native_query++;
    EGLSurface result = r_eglCreateWindowSurface(display,cfg,win,attrs);
    native_query--;
    remember_egl_surface(display,result,(Window)win);
    return result;
}
EGLSurface eglCreatePlatformWindowSurface(EGLDisplay display, EGLConfig cfg, void *win, const EGLAttrib *attrs)
{
    API(); int handled = 0;
    if (wayland_display(display)) {
        EGLSurface result = wayland_window_surface(display,cfg,win,attrs,create_platform_window,&handled);
        if (handled) return result;
    }
    native_query++;
    EGLSurface result = r_eglCreatePlatformWindowSurface(display,cfg,win,attrs);
    native_query--;
    if (egl_x11(display)) remember_egl_surface(display,result,*(Window *)win);
    return result;
}
EGLSurface eglCreatePlatformWindowSurfaceEXT(EGLDisplay display, EGLConfig cfg, void *win, const EGLint *attrs)
{
    API(); int handled = 0;
    EGLAttrib *wide = wide_attribs(attrs);
    if (!wide) return EGL_NO_SURFACE;
    EGLSurface result = EGL_NO_SURFACE;
    if (wayland_display(display)) result = wayland_window_surface(display,cfg,win,wide,create_platform_window_ext,&handled);
    if (!handled) {
        native_query++;
        result = create_platform_window_ext(display,cfg,win,wide);
        native_query--;
        if (egl_x11(display)) remember_egl_surface(display,result,*(Window *)win);
    }
    free(wide);
    return result;
}
EGLBoolean eglMakeCurrent(EGLDisplay display, EGLSurface draw, EGLSurface read, EGLContext context)
{
    API(); ContextState *previous = current;
    Display *x11 = egl_x11(display);
    EGLint api = 0;
    if (context != EGL_NO_CONTEXT) r_eglQueryContext(display,context,EGL_CONTEXT_CLIENT_TYPE,&api);
    WindowState *w = NULL;
    if (x11 && api == EGL_OPENGL_API) {
        for (w = windows; w && !(w->display == x11 && w->egl_surface == draw); w = w->next) {}
    }
    WindowState *wayland = (api == EGL_OPENGL_API || api == EGL_OPENGL_ES_API) && draw != EGL_NO_SURFACE ? find_wayland_surface(draw) : NULL;
    if (getenv("GL_STEREO_DEBUG")) fprintf(stderr,"egl make current draw=%p context=%p api=%x two-view=%p\n",(void*)draw,(void*)context,api,(void*)wayland);
    if (wayland) bind_wayland_context(wayland,context,api == EGL_OPENGL_ES_API);
    else if (w) { bind_context(x11,w->window,(GLXContext)context); current->egl = 1; }
    else current = NULL;
    native_query++;
    EGLBoolean result = r_eglMakeCurrent(display,draw,read,context);
    native_query--;
    if (!result) current = previous;
    else initial_viewport();
    return result;
}
EGLBoolean eglSwapBuffers(EGLDisplay display, EGLSurface surface)
{
    API(); native_query++;
    static _Thread_local unsigned swaps;
    if (getenv("GL_STEREO_DEBUG") && current && current->window && current->window->wl_window && !(swaps++ % 100)) {
        EGLint width = 0; r_eglQuerySurface(display,surface,EGL_WIDTH,&width);
        GLint viewport[4]; r_glGetIntegerv(GL_VIEWPORT,viewport);
        fprintf(stderr,"swap %u logical=%d native surface=%d window=%d attached=%d viewport %d %d %d %d\n",swaps,current->window->width,width,
                current->window->wl_window->width,current->window->wl_window->attached_width,viewport[0],viewport[1],viewport[2],viewport[3]);
    }
    if (current && current->egl && current->window && current->window->egl_surface == surface) dump(current->window);
    EGLBoolean result = r_eglSwapBuffers(display,surface);
    native_query--; return result;
}
EGLBoolean eglQuerySurface(EGLDisplay display, EGLSurface surface, EGLint attribute, EGLint *value)
{
    API();
    if (attribute == EGL_MULTIVIEW_VIEW_COUNT_EXT && wayland_views(wayland_display(display))) {
        *value = find_wayland_surface(surface) ? 2 : 1;
        return EGL_TRUE;
    }
    EGLBoolean result = r_eglQuerySurface(display,surface,attribute,value);
    if (!native_query && result && attribute == EGL_WIDTH) {
        for (WindowState *w = windows; w; w = w->next)
            if (w->egl_surface == surface && w->active) { *value /= 2; break; }
    }
    return result;
}
EGLBoolean eglDestroyContext(EGLDisplay display, EGLContext context)
{
    API(); EGLBoolean result = r_eglDestroyContext(display,context);
    if (result) {
        pthread_mutex_lock(&state_lock);
        ContextState **p = &contexts;
        while (*p && !((*p)->egl && (*p)->context == (GLXContext)context)) p = &(*p)->next;
        if (*p) { ContextState *old = *p; *p = old->next; if (current == old) current = NULL; free_texture_records(old); free(old->extensions); free(old); }
        pthread_mutex_unlock(&state_lock);
    }
    return result;
}
EGLBoolean eglDestroySurface(EGLDisplay display, EGLSurface surface)
{
    API(); EGLBoolean result = r_eglDestroySurface(display,surface);
    if (result) {
        pthread_mutex_lock(&state_lock);
        WindowState *wayland = find_wayland_surface(surface);
        if (wayland) forget_wayland_window(wayland, 1);
        for (WindowState *w = windows; w; w = w->next)
            if (w->egl_surface == surface) w->egl_surface = EGL_NO_SURFACE;
        pthread_mutex_unlock(&state_lock);
    }
    return result;
}

static EGLBoolean swap_damage(EGLDisplay display, EGLSurface surface, const EGLint *rects, EGLint count, const char *name)
{
    API(); native_query++;
    PFNEGLSWAPBUFFERSWITHDAMAGEKHRPROC swap = (PFNEGLSWAPBUFFERSWITHDAMAGEKHRPROC)r_eglGetProcAddress(name);
    if (!swap) { native_query--; return EGL_FALSE; }
    WindowState *w = current && current->egl ? current->window : NULL;
    EGLint *packed = NULL;
    if (w && w->egl_surface == surface) {
        dump(w);
        if (count > 0 && count < 1000000 && rects) {
            packed = malloc((size_t)count*8*sizeof(*packed));
            if (packed) for (int i = 0; i < count; ++i) {
                memcpy(packed+8*i,rects+4*i,4*sizeof(*packed));
                memcpy(packed+8*i+4,rects+4*i,4*sizeof(*packed));
                packed[8*i+4] += w->width;
            }
            /* Without scratch memory, present the whole frame. */
            rects = packed; count = packed ? count*2 : 0;
        }
    }
    EGLBoolean result = swap(display,surface,rects,count);
    free(packed); native_query--; return result;
}
EGLBoolean eglSwapBuffersWithDamageKHR(EGLDisplay d, EGLSurface s, const EGLint *r, EGLint n)
{ return swap_damage(d,s,r,n,"eglSwapBuffersWithDamageKHR"); }
EGLBoolean eglSwapBuffersWithDamageEXT(EGLDisplay d, EGLSurface s, const EGLint *r, EGLint n)
{ return swap_damage(d,s,r,n,"eglSwapBuffersWithDamageEXT"); }
