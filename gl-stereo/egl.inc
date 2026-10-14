/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Included with the core's private context/window state. Only X11 desktop GL. */
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
    if (display != EGL_DEFAULT_DISPLAY) remember_egl_display(result, (Display *)display);
    return result;
}
EGLDisplay eglGetPlatformDisplay(EGLenum platform, void *display, const EGLAttrib *attrs)
{
    API(); EGLDisplay result = r_eglGetPlatformDisplay(platform,display,attrs);
    if (platform == EGL_PLATFORM_X11_EXT && display) remember_egl_display(result,display);
    return result;
}
static void remember_egl_surface(EGLDisplay display, EGLSurface surface, Window win)
{
    pthread_mutex_lock(&state_lock);
    WindowState *w = find_window(egl_x11(display), win);
    if (w) w->egl_surface = surface;
    pthread_mutex_unlock(&state_lock);
}
EGLSurface eglCreateWindowSurface(EGLDisplay display, EGLConfig cfg, EGLNativeWindowType win, const EGLint *attrs)
{
    API(); native_query++;
    EGLSurface result = r_eglCreateWindowSurface(display,cfg,win,attrs);
    native_query--;
    remember_egl_surface(display,result,(Window)win);
    return result;
}
EGLSurface eglCreatePlatformWindowSurface(EGLDisplay display, EGLConfig cfg, void *win, const EGLAttrib *attrs)
{
    API(); native_query++;
    EGLSurface result = r_eglCreatePlatformWindowSurface(display,cfg,win,attrs);
    native_query--;
    if (egl_x11(display)) remember_egl_surface(display,result,*(Window *)win);
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
    if (w) { bind_context(x11,w->window,(GLXContext)context); current->egl = 1; }
    else current = NULL;
    native_query++;
    EGLBoolean result = r_eglMakeCurrent(display,draw,read,context);
    native_query--;
    if (!result) current = previous;
    return result;
}
EGLBoolean eglSwapBuffers(EGLDisplay display, EGLSurface surface)
{
    API(); native_query++;
    if (current && current->egl && current->window && current->window->egl_surface == surface) dump(current->window);
    EGLBoolean result = r_eglSwapBuffers(display,surface);
    native_query--; return result;
}
EGLBoolean eglQuerySurface(EGLDisplay display, EGLSurface surface, EGLint attribute, EGLint *value)
{
    API(); EGLBoolean result = r_eglQuerySurface(display,surface,attribute,value);
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
        if (*p) { ContextState *old = *p; *p = old->next; if (current == old) current = NULL; free_texture_records(old); free(old); }
        pthread_mutex_unlock(&state_lock);
    }
    return result;
}
EGLBoolean eglDestroySurface(EGLDisplay display, EGLSurface surface)
{
    API(); EGLBoolean result = r_eglDestroySurface(display,surface);
    if (result) for (WindowState *w = windows; w; w = w->next)
        if (w->egl_surface == surface) w->egl_surface = EGL_NO_SURFACE;
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
