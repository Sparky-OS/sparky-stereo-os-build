/* LD_PRELOAD: prints the EGLConfig of every window surface created (channel sizes, component type). */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
static void show(const char *fn, EGLDisplay d, EGLConfig c)
{
    EGLint r = 0, g = 0, b = 0, al = 0, id = 0, ct = 0;
    eglGetConfigAttrib(d, c, EGL_RED_SIZE, &r); eglGetConfigAttrib(d, c, EGL_GREEN_SIZE, &g);
    eglGetConfigAttrib(d, c, EGL_BLUE_SIZE, &b); eglGetConfigAttrib(d, c, EGL_ALPHA_SIZE, &al);
    eglGetConfigAttrib(d, c, EGL_CONFIG_ID, &id); eglGetConfigAttrib(d, c, EGL_COLOR_COMPONENT_TYPE_EXT, &ct);
    fprintf(stderr, "EGLSHIM %s: config id %d r=%d g=%d b=%d a=%d %s\n", fn, id, r, g, b, al, ct == EGL_COLOR_COMPONENT_TYPE_FLOAT_EXT ? "float" : "unorm");
}
EGLSurface eglCreateWindowSurface(EGLDisplay d, EGLConfig c, EGLNativeWindowType w, const EGLint *a)
{
    EGLSurface (*real)(EGLDisplay, EGLConfig, EGLNativeWindowType, const EGLint *) = dlsym(RTLD_NEXT, "eglCreateWindowSurface");
    show("eglCreateWindowSurface", d, c);
    return real(d, c, w, a);
}
EGLSurface eglCreatePlatformWindowSurface(EGLDisplay d, EGLConfig c, void *w, const EGLAttrib *a)
{
    EGLSurface (*real)(EGLDisplay, EGLConfig, void *, const EGLAttrib *) = dlsym(RTLD_NEXT, "eglCreatePlatformWindowSurface");
    show("eglCreatePlatformWindowSurface", d, c);
    return real(d, c, w, a);
}
EGLSurface eglCreatePlatformWindowSurfaceEXT(EGLDisplay d, EGLConfig c, void *w, const EGLint *a)
{
    EGLSurface (*real)(EGLDisplay, EGLConfig, void *, const EGLint *) = dlsym(RTLD_NEXT, "eglCreatePlatformWindowSurfaceEXT");
    show("eglCreatePlatformWindowSurfaceEXT", d, c);
    return real(d, c, w, a);
}
__attribute__((constructor)) static void hello(void) { fprintf(stderr, "EGLSHIM loaded\n"); }
