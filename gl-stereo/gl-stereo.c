/* SPDX-License-Identifier: GPL-2.0-or-later */
#define _GNU_SOURCE
#define GL_GLEXT_PROTOTYPES
#include <GL/gl.h>
#include <GL/glx.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stereo-declare.h>

/* Only pixel-producing calls are interposed. Matrix and attribute operations
 * remain the driver's state, including its stacks and display-list semantics. */
#define GL_API(X) \
 X(glGetFloatv) X(glDrawBuffer) X(glDrawBuffers) X(glGetIntegerv) X(glGetDoublev) X(glGetBooleanv) X(glIsEnabled) \
 X(glAccum) X(glCopyPixels) X(glCopyTexImage2D) X(glCopyTexSubImage2D) X(glMatrixMode) X(glLoadMatrixd) X(glPushMatrix) X(glPopMatrix) \
 X(glPushAttrib) X(glPopAttrib) X(glViewport) X(glScissor) X(glEnable) X(glDisable) \
 X(glBegin) X(glEnd) X(glGenLists) X(glDeleteLists) X(glNewList) X(glEndList) \
 X(glCallList) X(glCallLists) X(glClear) X(glDrawArrays) X(glDrawElements) \
 X(glDrawRangeElements) X(glMultiDrawArrays) X(glMultiDrawElements) \
 X(glDrawPixels) X(glBitmap) X(glWindowPos3dv) X(glEvalMesh1) X(glEvalMesh2) \
 X(glBindFramebuffer) X(glBlitFramebuffer) X(glRectd) X(glReadPixels) X(glReadBuffer) X(glPixelStorei) X(glBindBuffer) \
 X(glXMakeCurrent) X(glXMakeContextCurrent) X(glXDestroyContext) \
 X(glXSwapBuffers) X(glXGetProcAddressARB) X(glXQueryDrawable) \
 X(glXCreateWindow) X(glXDestroyWindow) \
 X(glXChooseVisual) X(glXGetConfig) X(glXGetFBConfigs) X(glXChooseFBConfig) \
 X(glXGetFBConfigAttrib) X(glXGetVisualFromFBConfig) X(glXCreateContext) X(glXCreateNewContext) \
 X(glXCreatePbuffer) X(glXCreatePixmap)
#define EGL_API(X) \
 X(eglGetDisplay) X(eglGetPlatformDisplay) X(eglCreateWindowSurface) \
 X(eglCreatePlatformWindowSurface) X(eglMakeCurrent) X(eglSwapBuffers) \
 X(eglDestroyContext) X(eglDestroySurface) X(eglQuerySurface) X(eglQueryContext) X(eglGetProcAddress)
#define X_API(X) \
 X(XFree) X(XCreateWindow) X(XCreateSimpleWindow) X(XDestroyWindow) X(XResizeWindow) \
 X(XMoveResizeWindow) X(XConfigureWindow) X(XGetWindowAttributes) X(XGetGeometry) \
 X(XNextEvent) X(XWindowEvent) X(XMaskEvent) X(XCheckWindowEvent) \
 X(XCheckMaskEvent) X(XCheckTypedEvent) X(XCheckTypedWindowEvent) X(XPeekEvent) \
 X(XIfEvent) X(XPeekIfEvent) X(XCheckIfEvent)
#define DECLARE(name) static __typeof__(&name) r_##name;
GL_API(DECLARE)
EGL_API(DECLARE)
X_API(DECLARE)
#undef DECLARE
static pthread_once_t api_once = PTHREAD_ONCE_INIT;
static void *gl_handle, *x_handle, *egl_handle;
static _Thread_local int resolving;
static void *lookup_symbol(void *handle, const char *name)
{
    void *(*lookup)(void *, const char *) = dlvsym(RTLD_NEXT,"dlsym","GLIBC_2.2.5");
    if (!lookup) abort();
    return lookup(handle,name);
}
static void init_api(void)
{
    resolving++;
    gl_handle = dlopen("libGL.so.1", RTLD_NOW | RTLD_LOCAL);
    egl_handle = dlopen("libEGL.so.1", RTLD_NOW | RTLD_LOCAL);
    x_handle = dlopen("libX11.so.6", RTLD_NOW | RTLD_LOCAL);
    if (!gl_handle || !x_handle) { fputs("gl-stereo: missing GL/X11 runtime\n", stderr); abort(); }
#define LOAD_GL(name) r_##name = lookup_symbol(gl_handle, #name);
#define LOAD_EGL(name) r_##name = lookup_symbol(egl_handle, #name);
#define LOAD_X(name) r_##name = lookup_symbol(x_handle, #name);
    GL_API(LOAD_GL)
    EGL_API(LOAD_EGL)
    X_API(LOAD_X)
#undef LOAD_GL
#undef LOAD_X
    resolving--;
}
#define API() pthread_once(&api_once, init_api)

static struct {
    int enabled, swap, dump;
    unsigned render_width, render_height;
    double percent, convergence;
    const char *dump_dir, *stats_path;
} config;
static double number(const char *name, double fallback, double lo, double hi)
{
    const char *s = getenv(name);
    if (!s) return fallback;
    char *end;
    errno = 0;
    double v = strtod(s, &end);
    if (errno || end == s || *end || !isfinite(v) || v < lo || v > hi) {
        fprintf(stderr, "gl-stereo: invalid %s; using %.6g\n", name, fallback);
        return fallback;
    }
    return v;
}
__attribute__((constructor)) static void configure(void)
{
    const char *s = getenv("GL_STEREO");
    config.enabled = s && !strcmp(s, "1");
    if (getenv("GL_STEREO_PASSTHROUGH")) config.enabled = 0;
    config.percent = number("GL_STEREO_SEPARATION", 2, 0, 10);
    config.convergence = number("GL_STEREO_CONVERGENCE", 0, 0.000001, 1e12);
    config.swap = number("GL_STEREO_SWAP", 0, 0, 1);
    config.dump = number("GL_STEREO_DUMP", 0, 0, 1000000);
    config.dump_dir = getenv("GL_STEREO_DUMP_DIR");
    config.stats_path = getenv("GL_STEREO_STATS");
    const char *resolution = getenv("GL_STEREO_RENDER_RESOLUTION");
    if (resolution) {
        char extra;
        unsigned width, height;
        if (sscanf(resolution, "%ux%u%c", &width, &height, &extra) == 2 &&
            width >= 64 && width <= 8192 && height >= 64 && height <= 8192) {
            config.render_width = width; config.render_height = height;
        } else fputs("gl-stereo: invalid render resolution; using window size\n", stderr);
    }
}

static unsigned warnings;
static void warn_once(unsigned bit, const char *message)
{
    if (!config.enabled || !getenv("GL_STEREO_LOG")) return;
    unsigned previous = __atomic_fetch_or(&warnings,bit,__ATOMIC_RELAXED);
    if (!(previous & bit)) fprintf(stderr,"gl-stereo: %s\n",message);
}
static unsigned long stats_logical, stats_issued;
#define COUNT(which) do { if (config.stats_path) __atomic_add_fetch(&stats_##which,1,__ATOMIC_RELAXED); } while (0)
__attribute__((destructor)) static void write_stats(void)
{
    if (!config.stats_path) return;
    int fd = open(config.stats_path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);
    if (fd < 0) return;
    FILE *f = fdopen(fd,"w");
    if (!f) { close(fd); return; }
    fprintf(f,"{\"logical\":%lu,\"issued\":%lu}\n",stats_logical,stats_issued);
    fclose(f);
}

typedef struct window_state {
    Display *display;
    Window window;
    GLXDrawable drawable;
    EGLSurface egl_surface;
    int active, width, height, compositor_sizes;
    unsigned long resize_serial;
    unsigned frame;
    double last_projection[16], last_convergence;
    struct window_state *next;
} WindowState;
typedef struct context_state {
    GLXContext context;
    int egl, quad;
    GLenum draw_buffer, read_buffer;
    GLuint primitive;
    int compiling, immediate;
    WindowState *window;
    struct context_state *next;
} ContextState;
static pthread_mutex_t state_lock = PTHREAD_MUTEX_INITIALIZER;
static WindowState *windows;
static ContextState *contexts;
static _Thread_local ContextState *current;
static _Thread_local int native_query;

static WindowState *find_window(Display *d, XID w)
{
    WindowState *p;
    for (p = windows; p; p = p->next)
        if (p->display == d && (p->window == w || p->drawable == w)) return p;
    return NULL;
}
static void remember_window(Display *d, Window w, unsigned width, unsigned height)
{
    if (!config.enabled || !w) return;
    pthread_mutex_lock(&state_lock);
    WindowState *p = calloc(1, sizeof(*p));
    if (p) {
        p->display = d; p->window = p->drawable = w;
        p->width = width; p->height = height;
        p->next = windows; windows = p;
    }
    pthread_mutex_unlock(&state_lock);
}
static void bind_context(Display *d, GLXDrawable draw, GLXContext context)
{
    current = NULL;
    if (!config.enabled || !context) return;
    pthread_mutex_lock(&state_lock);
    ContextState *p;
    for (p = contexts; p && p->context != context; p = p->next) {}
    if (!p) {
        p = calloc(1, sizeof(*p));
        if (!p) abort();
        p->context = context; p->next = contexts; contexts = p;
    }
    p->window = find_window(d, draw);
    WindowState *w = p->window;
    if (w && !w->active) {
        XWindowAttributes a;
        if (r_XGetWindowAttributes(d, w->window, &a)) {
            w->width = config.render_width ? (int)config.render_width : a.width;
            w->height = config.render_height ? (int)config.render_height : a.height; w->active = 1;
            int support = stereo_supported_x11(d);
            w->compositor_sizes = support >= 3;
            w->resize_serial = NextRequest(d);
            r_XResizeWindow(d, w->window, (w->compositor_sizes ? 1 : 2) * w->width, w->height);
            XSync(d, False);
            if (support >= 1) {
                int result = stereo_declare_x11_format(d, w->window, STEREO_SBS_FULL);
                if (result) fprintf(stderr, "gl-stereo: declaration failed: %d\n", result);
            }
        }
    }
    if (getenv("GL_STEREO_DEBUG")) fprintf(stderr,"bind context=%p drawable=%lu window=%p\n",(void*)context,draw,(void*)w);
    current = p;
    pthread_mutex_unlock(&state_lock);
}

typedef struct {
    double projection[16];
    GLint viewport[4], scissor[4], mode;
    GLboolean scissor_on;
    double convergence;
} DrawState;
static int stereo_target(void)
{
    if (!current || !current->window || !current->window->active || current->compiling) return 0;
    GLint fbo, mode;
    r_glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &fbo);
    r_glGetIntegerv(GL_RENDER_MODE, &mode);
    return !fbo && mode == GL_RENDER;
}
static void save_draw(DrawState *s)
{
    if (!current->quad) {
        r_glGetDoublev(GL_PROJECTION_MATRIX, s->projection);
        r_glGetIntegerv(GL_MATRIX_MODE, &s->mode);
    } else { memset(s->projection,0,sizeof(s->projection)); s->mode = 0; }
    r_glGetIntegerv(GL_VIEWPORT, s->viewport);
    r_glGetIntegerv(GL_SCISSOR_BOX, s->scissor);
    s->scissor_on = r_glIsEnabled(GL_SCISSOR_TEST);
    double near = s->projection[14] / (s->projection[10] - 1);
    s->convergence = config.convergence ? config.convergence :
                     (isfinite(near) && near > 0 ? 5 * near : 5);
}
static void set_eye(const DrawState *s, int eye)
{
    WindowState *w = current->window;
    double p[16];
    if (fabs(s->projection[11]+1) < 1e-6) {
        memcpy(w->last_projection, s->projection, sizeof(w->last_projection));
        w->last_convergence = s->convergence;
    }
    memcpy(p, s->projection, sizeof(p));
    if (!current->quad && fabs(p[11] + 1) < 1e-6 && fabs(p[15]) < 1e-6) {
        double shift = (eye ? 1 : -1) * config.percent / 100;
        if (config.swap) shift = -shift;
        for (int col = 0; col < 4; ++col) p[4*col] += shift * s->projection[4*col+3];
        p[12] -= shift * s->convergence;
    }
    if (!current->quad) {
        r_glMatrixMode(GL_PROJECTION); r_glLoadMatrixd(p); r_glMatrixMode(s->mode);
    }
    r_glViewport(eye*w->width+s->viewport[0], s->viewport[1], s->viewport[2], s->viewport[3]);
    int x0 = 0, y0 = 0, x1 = w->width, y1 = w->height;
    if (s->scissor_on) {
        x0 = s->scissor[0] > 0 ? s->scissor[0] : 0;
        y0 = s->scissor[1] > 0 ? s->scissor[1] : 0;
        if (s->scissor[0]+s->scissor[2] < x1) x1 = s->scissor[0]+s->scissor[2];
        if (s->scissor[1]+s->scissor[3] < y1) y1 = s->scissor[1]+s->scissor[3];
    }
    r_glEnable(GL_SCISSOR_TEST);
    r_glScissor(eye*w->width+x0, y0, x1 > x0 ? x1-x0 : 0, y1 > y0 ? y1-y0 : 0);
}
static void restore_draw(const DrawState *s)
{
    if (!current->quad) { r_glMatrixMode(GL_PROJECTION); r_glLoadMatrixd(s->projection); r_glMatrixMode(s->mode); }
    r_glViewport(s->viewport[0], s->viewport[1], s->viewport[2], s->viewport[3]);
    r_glScissor(s->scissor[0], s->scissor[1], s->scissor[2], s->scissor[3]);
    if (!s->scissor_on) r_glDisable(GL_SCISSOR_TEST);
}
/* State changes within a display list must persist once. The left pass is
 * isolated; the right pass supplies the application's resulting state. */
static int selected_eye(int eye)
{
    if (!current->quad) return 1;
    GLenum buffer = current->draw_buffer;
    if (buffer == GL_NONE) return 0;
    if (buffer == GL_BACK_RIGHT || buffer == GL_FRONT_RIGHT || buffer == GL_RIGHT) return eye == 1;
    if (buffer == GL_BACK_LEFT || buffer == GL_FRONT_LEFT || buffer == GL_LEFT) return eye == 0;
    return 1;
}
static void isolate_left(void)
{
    r_glPushAttrib(GL_ALL_ATTRIB_BITS);
    r_glMatrixMode(GL_MODELVIEW); r_glPushMatrix();
    r_glMatrixMode(GL_TEXTURE); r_glPushMatrix();
    r_glMatrixMode(GL_PROJECTION); r_glPushMatrix();
}
static void finish_left(void)
{
    r_glMatrixMode(GL_PROJECTION); r_glPopMatrix();
    r_glMatrixMode(GL_TEXTURE); r_glPopMatrix();
    r_glMatrixMode(GL_MODELVIEW); r_glPopMatrix();
    r_glPopAttrib();
}
#define DRAW(call) do { \
    API(); native_query++; \
    if (!stereo_target()) { call; native_query--; return; } \
    COUNT(logical); DrawState saved; save_draw(&saved); \
    if (selected_eye(0)) { \
        if (!current->quad && selected_eye(1)) isolate_left(); \
        set_eye(&saved, 0); COUNT(issued); call; \
        if (!current->quad && selected_eye(1)) finish_left(); \
    } \
    if (selected_eye(1)) { set_eye(&saved, 1); COUNT(issued); call; } restore_draw(&saved); native_query--; \
} while (0)

#include "frame-stream.inc"

static void dump(WindowState *w)
{
    stream_frame(w);
    if (!config.dump_dir || !config.dump || w->frame++ != (unsigned)config.dump - 1) return;
    int width = w->width * (w->active ? 2 : 1), height = w->height;
    if (getenv("GL_STEREO_DEBUG")) {
        XWindowAttributes attr; r_XGetWindowAttributes(w->display,w->window,&attr);
        GLint vp[4]; r_glGetIntegerv(GL_VIEWPORT,vp);
        fprintf(stderr,"dump logical %dx%d native %dx%d viewport %d %d %d %d\n",w->width,w->height,attr.width,attr.height,vp[0],vp[1],vp[2],vp[3]);
    }
    if (width <= 0 || height <= 0 || width > 32768 || height > 32768) return;
    size_t stride = (size_t)width*3;
    unsigned char *pixels = malloc(stride*height);
    if (!pixels) return;
    GLint read, pack[6], pbo, framebuffer;
    r_glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING,&framebuffer);
    r_glBindFramebuffer(GL_READ_FRAMEBUFFER,0);
    const GLenum names[6] = {GL_PACK_ALIGNMENT, GL_PACK_ROW_LENGTH, GL_PACK_SKIP_PIXELS,
                            GL_PACK_SKIP_ROWS, GL_PACK_SWAP_BYTES, GL_PACK_LSB_FIRST};
    r_glGetIntegerv(GL_READ_BUFFER, &read);
    r_glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &pbo);
    r_glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
    for (int i = 0; i < 6; ++i) { r_glGetIntegerv(names[i], &pack[i]); r_glPixelStorei(names[i], i ? 0 : 1); }
    GLboolean double_buffer;
    r_glGetBooleanv(GL_DOUBLEBUFFER, &double_buffer);
    r_glReadBuffer(double_buffer ? GL_BACK : GL_FRONT);
    r_glReadPixels(0, 0, width, height, GL_RGB, GL_UNSIGNED_BYTE, pixels);
    float *depth = malloc((size_t)width*height*sizeof(float));
    if (depth) r_glReadPixels(0, 0, width, height, GL_DEPTH_COMPONENT, GL_FLOAT, depth);
    r_glReadBuffer(read);
    r_glBindFramebuffer(GL_READ_FRAMEBUFFER,framebuffer);
    for (int i = 0; i < 6; ++i) r_glPixelStorei(names[i], pack[i]);
    r_glBindBuffer(GL_PIXEL_PACK_BUFFER, pbo);
    char path[4096];
    int len = snprintf(path, sizeof(path), "%s/frame-%lu-%04u.ppm", config.dump_dir, w->window, w->frame);
    int fd = len > 0 && (size_t)len < sizeof(path) ? open(path, O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW, 0600) : -1;
    FILE *f = fd >= 0 ? fdopen(fd, "wb") : NULL;
    if (f) {
        fprintf(f, "P6\n%d %d\n255\n", width, height);
        for (int y = height-1; y >= 0; --y) fwrite(pixels+y*stride, 1, stride, f);
        fclose(f);
    } else if (fd >= 0) close(fd);
    if (depth) {
        snprintf(path, sizeof(path), "%s/frame-%lu-%04u.depth", config.dump_dir, w->window, w->frame);
        fd = open(path, O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW, 0600);
        f = fd >= 0 ? fdopen(fd, "wb") : NULL;
        if (f) { for (int y = height-1; y >= 0; --y) fwrite(depth+y*width, sizeof(float), width, f); fclose(f); }
        else if (fd >= 0) close(fd);
        free(depth);
        snprintf(path, sizeof(path), "%s/frame-%lu-%04u.txt", config.dump_dir, w->window, w->frame);
        fd = open(path, O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW, 0600);
        f = fd >= 0 ? fdopen(fd, "wb") : NULL;
        if (f) {
            fprintf(f, "%.17g %.17g %.17g %.17g\n", w->last_projection[10], w->last_projection[14], w->last_convergence, config.percent);
            fclose(f);
        } else if (fd >= 0) close(fd);
    }
    free(pixels);
}

static GLXFBConfig native_config(GLXFBConfig config, int *stereo);
#pragma GCC visibility push(default)
void glMatrixMode(GLenum mode)
{
    API();
    if (current && current->compiling && mode == GL_PROJECTION)
        warn_once(2,"projection-changing display list: automatic stereo is not supported");
    r_glMatrixMode(mode);
}
void glAccum(GLenum op, GLfloat value) { API(); warn_once(4,"glAccum passes through once over the native framebuffer"); r_glAccum(op,value); }
void glCopyPixels(GLint x, GLint y, GLsizei w, GLsizei h, GLenum type) { API(); warn_once(8,"glCopyPixels is mono-sourced and passes through once"); r_glCopyPixels(x,y,w,h,type); }
void glCopyTexImage2D(GLenum target, GLint level, GLenum format, GLint x, GLint y, GLsizei w, GLsizei h, GLint border)
{ API(); warn_once(16,"glCopyTexImage2D is mono-sourced and passes through once"); r_glCopyTexImage2D(target,level,format,x,y,w,h,border); }
void glCopyTexSubImage2D(GLenum target, GLint level, GLint dx, GLint dy, GLint x, GLint y, GLsizei w, GLsizei h)
{ API(); warn_once(32,"glCopyTexSubImage2D is mono-sourced and passes through once"); r_glCopyTexSubImage2D(target,level,dx,dy,x,y,w,h); }
void glBegin(GLenum mode)
{
    API();
    if (stereo_target()) {
        GLuint list = r_glGenLists(1);
        if (list) {
            current->primitive = list;
            current->immediate = 1;
            r_glNewList(list, GL_COMPILE);
        } else fputs("gl-stereo: primitive allocation failed; drawing once\n", stderr);
    }
    r_glBegin(mode);
}
void glEnd(void)
{
    API(); r_glEnd();
    if (current && current->immediate) {
        r_glEndList();
        GLuint list = current->primitive;
        current->immediate = 0;
        glCallList(list);
        r_glDeleteLists(list, 1);
    }
}
void glNewList(GLuint list, GLenum mode)
{
    API();
    if (current) current->compiling = 1;
    if (mode == GL_COMPILE_AND_EXECUTE) warn_once(1,"compile-and-execute list runs natively once during compilation; stereo execution not supported");
    r_glNewList(list, mode);
}
void glEndList(void)
{
    API(); r_glEndList();
    if (current) current->compiling = 0;
}
void glCallList(GLuint list) { DRAW(r_glCallList(list)); }
void glCallLists(GLsizei n, GLenum type, const void *lists) { DRAW(r_glCallLists(n, type, lists)); }
void glClear(GLbitfield mask) { DRAW(r_glClear(mask)); }
void glDrawArrays(GLenum mode, GLint first, GLsizei count) { DRAW(r_glDrawArrays(mode, first, count)); }
void glDrawElements(GLenum mode, GLsizei count, GLenum type, const void *indices) { DRAW(r_glDrawElements(mode, count, type, indices)); }
void glDrawRangeElements(GLenum mode, GLuint start, GLuint end, GLsizei count, GLenum type, const void *indices) { DRAW(r_glDrawRangeElements(mode, start, end, count, type, indices)); }
void glMultiDrawArrays(GLenum mode, const GLint *first, const GLsizei *count, GLsizei n) { DRAW(r_glMultiDrawArrays(mode, first, count, n)); }
void glMultiDrawElements(GLenum mode, const GLsizei *count, GLenum type, const void *const *indices, GLsizei n) { DRAW(r_glMultiDrawElements(mode, count, type, indices, n)); }
void glEvalMesh1(GLenum mode, GLint i1, GLint i2) { DRAW(r_glEvalMesh1(mode, i1, i2)); }
void glEvalMesh2(GLenum mode, GLint i1, GLint i2, GLint j1, GLint j2) { DRAW(r_glEvalMesh2(mode, i1, i2, j1, j2)); }
void glRectd(GLdouble x1, GLdouble y1, GLdouble x2, GLdouble y2) { DRAW(r_glRectd(x1, y1, x2, y2)); }
void glRectf(GLfloat x1, GLfloat y1, GLfloat x2, GLfloat y2) { glRectd(x1, y1, x2, y2); }
void glRecti(GLint x1, GLint y1, GLint x2, GLint y2) { glRectd(x1, y1, x2, y2); }
void glRects(GLshort x1, GLshort y1, GLshort x2, GLshort y2) { glRectd(x1, y1, x2, y2); }
void glRectdv(const GLdouble *a, const GLdouble *b) { glRectd(a[0], a[1], b[0], b[1]); }
void glRectfv(const GLfloat *a, const GLfloat *b) { glRectd(a[0], a[1], b[0], b[1]); }
void glRectiv(const GLint *a, const GLint *b) { glRectd(a[0], a[1], b[0], b[1]); }
void glRectsv(const GLshort *a, const GLshort *b) { glRectd(a[0], a[1], b[0], b[1]); }
/* Raster images are screen-space overlays. Keep bitmap movement once and
 * preserve the raster colour/texture attributes through glPushAttrib. */
#define RASTER_DRAW(call) do { \
    API(); if (!stereo_target()) { call; return; } \
    GLboolean valid; r_glGetBooleanv(GL_CURRENT_RASTER_POSITION_VALID, &valid); \
    if (!valid) { call; return; } \
    DrawState saved; save_draw(&saved); \
    double pos[4]; r_glGetDoublev(GL_CURRENT_RASTER_POSITION, pos); \
    r_glPushAttrib(GL_CURRENT_BIT); set_eye(&saved, 1); \
    double right[3] = {pos[0]+current->window->width, pos[1], pos[2]}; \
    r_glWindowPos3dv(right); call; r_glPopAttrib(); \
    set_eye(&saved, 0); call; restore_draw(&saved); \
} while (0)
void glBitmap(GLsizei w, GLsizei h, GLfloat x0, GLfloat y0, GLfloat x1, GLfloat y1, const GLubyte *bits) { RASTER_DRAW(r_glBitmap(w, h, x0, y0, x1, y1, bits)); }
void glDrawPixels(GLsizei w, GLsizei h, GLenum format, GLenum type, const void *pixels) { RASTER_DRAW(r_glDrawPixels(w, h, format, type, pixels)); }

Bool glXMakeCurrent(Display *d, GLXDrawable draw, GLXContext context)
{
    API(); ContextState *previous = current;
    bind_context(d, draw, context);
    native_query++;
    Bool ok = r_glXMakeCurrent(d, draw, context);
    native_query--;
    if (!ok) current = previous;
    return ok;
}
Bool glXMakeContextCurrent(Display *d, GLXDrawable draw, GLXDrawable read, GLXContext context)
{
    API(); ContextState *previous = current;
    bind_context(d, draw, context);
    native_query++;
    Bool ok = r_glXMakeContextCurrent(d, draw, read, context);
    native_query--;
    if (!ok) current = previous;
    return ok;
}
void glXDestroyContext(Display *d, GLXContext context)
{
    API(); r_glXDestroyContext(d, context);
    pthread_mutex_lock(&state_lock);
    ContextState **p = &contexts;
    while (*p && (*p)->context != context) p = &(*p)->next;
    if (*p) { ContextState *old = *p; *p = old->next; if (current == old) current = NULL; free(old); }
    pthread_mutex_unlock(&state_lock);
}
void glXSwapBuffers(Display *d, GLXDrawable draw)
{
    API();
    if (current && current->window && current->window->drawable == draw) dump(current->window);
    native_query++;
    r_glXSwapBuffers(d, draw);
    native_query--;
}
int64_t glXSwapBuffersMscOML(Display *d, GLXDrawable draw, int64_t target, int64_t divisor, int64_t remainder)
{
    API(); native_query++;
    if (current && current->window && current->window->drawable == draw) dump(current->window);
    PFNGLXSWAPBUFFERSMSCOMLPROC swap = (PFNGLXSWAPBUFFERSMSCOMLPROC)r_glXGetProcAddressARB((const GLubyte *)"glXSwapBuffersMscOML");
    int64_t result = swap(d,draw,target,divisor,remainder);
    native_query--; return result;
}
GLXWindow glXCreateWindow(Display *d, GLXFBConfig fb, Window win, const int *attrs)
{
    API(); int stereo; fb = native_config(fb,&stereo);
    native_query++; GLXWindow draw = r_glXCreateWindow(d, fb, win, attrs); native_query--;
    pthread_mutex_lock(&state_lock);
    WindowState *w = find_window(d, win); if (w) w->drawable = draw;
    pthread_mutex_unlock(&state_lock);
    return draw;
}
void glXDestroyWindow(Display *d, GLXWindow draw)
{
    API(); r_glXDestroyWindow(d, draw);
    pthread_mutex_lock(&state_lock);
    WindowState *w = find_window(d, draw); if (w) w->drawable = w->window;
    pthread_mutex_unlock(&state_lock);
}
void glXQueryDrawable(Display *d, GLXDrawable draw, int attribute, unsigned *value)
{
    API(); r_glXQueryDrawable(d, draw, attribute, value);
    if (getenv("GL_STEREO_DEBUG")) fprintf(stderr,"query drawable native=%d attr=%x value=%u\n",native_query,attribute,*value);
    pthread_mutex_lock(&state_lock);
    WindowState *w = find_window(d, draw);
    if (!native_query && w && w->active && attribute == GLX_WIDTH) *value /= 2;
    pthread_mutex_unlock(&state_lock);
}
Window XCreateWindow(Display *d, Window parent, int x, int y, unsigned width, unsigned height,
                     unsigned border, int depth, unsigned class, Visual *visual,
                     unsigned long mask, XSetWindowAttributes *attrs)
{
    API(); Window w = r_XCreateWindow(d, parent, x, y, width, height, border, depth, class, visual, mask, attrs);
    if (getenv("GL_STEREO_DEBUG")) fprintf(stderr,"create window=%lu size=%ux%u\n",w,width,height);
    remember_window(d, w, width, height); return w;
}
Window XCreateSimpleWindow(Display *d, Window parent, int x, int y, unsigned width, unsigned height,
                           unsigned border_width, unsigned long border, unsigned long background)
{
    API(); Window w = r_XCreateSimpleWindow(d, parent, x, y, width, height, border_width, border, background);
    if (getenv("GL_STEREO_DEBUG")) fprintf(stderr,"create window=%lu size=%ux%u\n",w,width,height);
    remember_window(d, w, width, height); return w;
}
static unsigned native_width(Display *d, Window win, unsigned width, unsigned height)
{
    pthread_mutex_lock(&state_lock);
    WindowState *w = find_window(d, win);
    if (w && w->active) { w->width = width; w->height = height; if (!w->compositor_sizes) width *= 2; }
    pthread_mutex_unlock(&state_lock);
    return width;
}
int XResizeWindow(Display *d, Window w, unsigned width, unsigned height)
{ API(); return r_XResizeWindow(d, w, native_width(d, w, width, height), height); }
int XMoveResizeWindow(Display *d, Window w, int x, int y, unsigned width, unsigned height)
{ API(); return r_XMoveResizeWindow(d, w, x, y, native_width(d, w, width, height), height); }
int XConfigureWindow(Display *d, Window win, unsigned mask, XWindowChanges *changes)
{
    API(); XWindowChanges c = *changes;
    pthread_mutex_lock(&state_lock);
    WindowState *w = find_window(d, win);
    if (w && w->active) {
        if (mask & CWWidth) { w->width = c.width; if (!w->compositor_sizes) c.width *= 2; }
        if (mask & CWHeight) w->height = c.height;
    }
    pthread_mutex_unlock(&state_lock);
    return r_XConfigureWindow(d, win, mask, &c);
}
Status XGetWindowAttributes(Display *d, Window win, XWindowAttributes *attrs)
{
    API(); Status ok = r_XGetWindowAttributes(d, win, attrs);
    pthread_mutex_lock(&state_lock);
    WindowState *w = find_window(d, win);
    if (getenv("GL_STEREO_DEBUG")) fprintf(stderr,"attributes native_query=%d width=%d window=%lu\n",native_query,attrs->width,win);
    if (!native_query && ok && w && w->active) { attrs->width /= 2; w->width = attrs->width; w->height = attrs->height; }
    pthread_mutex_unlock(&state_lock);
    return ok;
}
Status XGetGeometry(Display *d, Drawable win, Window *root, int *x, int *y,
                    unsigned *width, unsigned *height, unsigned *border, unsigned *depth)
{
    API(); Status ok = r_XGetGeometry(d, win, root, x, y, width, height, border, depth);
    pthread_mutex_lock(&state_lock);
    WindowState *w = find_window(d, win); if (!native_query && ok && w && w->active) *width /= 2;
    pthread_mutex_unlock(&state_lock);
    return ok;
}
int XDestroyWindow(Display *d, Window win)
{
    API();
    pthread_mutex_lock(&state_lock);
    WindowState **p = &windows;
    while (*p && !((*p)->display == d && (*p)->window == win)) p = &(*p)->next;
    if (*p) {
        WindowState *old = *p; *p = old->next;
        for (ContextState *c = contexts; c; c = c->next) if (c->window == old) c->window = NULL;
        free(old);
    }
    pthread_mutex_unlock(&state_lock);
    return r_XDestroyWindow(d, win);
}
static void filter_event(Display *d, XEvent *event)
{
    if (event->type != ConfigureNotify) return;
    pthread_mutex_lock(&state_lock);
    WindowState *w = find_window(d, event->xconfigure.window);
    if (w && w->active && event->xconfigure.serial >= w->resize_serial) {
        if (getenv("GL_STEREO_DEBUG")) fprintf(stderr,"configure width=%d serial=%lu resize=%lu\n",event->xconfigure.width,event->xconfigure.serial,w->resize_serial);
        if (!w->compositor_sizes || !event->xconfigure.send_event) event->xconfigure.width /= 2;
        w->width = event->xconfigure.width; w->height = event->xconfigure.height;
    }
    pthread_mutex_unlock(&state_lock);
}
int XNextEvent(Display *d, XEvent *e) { API(); int r = r_XNextEvent(d,e); filter_event(d,e); return r; }
int XPeekEvent(Display *d, XEvent *e) { API(); int r = r_XPeekEvent(d,e); filter_event(d,e); return r; }
int XWindowEvent(Display *d, Window w, long m, XEvent *e) { API(); int r = r_XWindowEvent(d,w,m,e); filter_event(d,e); return r; }
int XMaskEvent(Display *d, long m, XEvent *e) { API(); int r = r_XMaskEvent(d,m,e); filter_event(d,e); return r; }
Bool XCheckWindowEvent(Display *d, Window w, long m, XEvent *e) { API(); Bool r = r_XCheckWindowEvent(d,w,m,e); if(r) filter_event(d,e); return r; }
Bool XCheckMaskEvent(Display *d, long m, XEvent *e) { API(); Bool r = r_XCheckMaskEvent(d,m,e); if(r) filter_event(d,e); return r; }
Bool XCheckTypedEvent(Display *d, int t, XEvent *e) { API(); Bool r = r_XCheckTypedEvent(d,t,e); if(r) filter_event(d,e); return r; }
Bool XCheckTypedWindowEvent(Display *d, Window w, int t, XEvent *e) { API(); Bool r = r_XCheckTypedWindowEvent(d,w,t,e); if(r) filter_event(d,e); return r; }

int XIfEvent(Display *d, XEvent *e, Bool (*predicate)(Display *,XEvent *,XPointer), XPointer arg)
{ API(); int r = r_XIfEvent(d,e,predicate,arg); filter_event(d,e); return r; }
int XPeekIfEvent(Display *d, XEvent *e, Bool (*predicate)(Display *,XEvent *,XPointer), XPointer arg)
{ API(); int r = r_XPeekIfEvent(d,e,predicate,arg); filter_event(d,e); return r; }
Bool XCheckIfEvent(Display *d, XEvent *e, Bool (*predicate)(Display *,XEvent *,XPointer), XPointer arg)
{ API(); Bool r = r_XCheckIfEvent(d,e,predicate,arg); if (r) filter_event(d,e); return r; }

#include "egl.inc"
#include "quad.inc"

#define WRAPPERS(X) X_API(X) \
 X(glXSwapBuffersMscOML) X(eglSwapBuffersWithDamageKHR) X(eglSwapBuffersWithDamageEXT) \
 X(glMatrixMode) X(glAccum) X(glCopyPixels) X(glCopyTexImage2D) X(glCopyTexSubImage2D) \
 X(glXGetProcAddress) X(glXGetProcAddressARB) X(eglGetProcAddress) X(glXChooseVisual) X(glXGetConfig) \
 X(glXGetFBConfigs) X(glXChooseFBConfig) X(glXGetFBConfigAttrib) X(glXGetVisualFromFBConfig) X(glXCreateContext) \
 X(glXCreateNewContext) X(glXCreateContextAttribsARB) X(glXCreatePbuffer) X(glXCreatePixmap) X(glBlitFramebuffer) \
 X(glDrawBuffer) X(glDrawBuffers) X(glReadBuffer) X(glReadPixels) X(glGetIntegerv) \
 X(glGetBooleanv) X(glGetFloatv) X(glGetDoublev) X(eglGetDisplay) X(eglGetPlatformDisplay) \
 X(eglCreateWindowSurface) X(eglCreatePlatformWindowSurface) X(eglMakeCurrent) X(eglSwapBuffers) X(eglQuerySurface) \
 X(eglDestroyContext) X(eglDestroySurface) X(glBegin) X(glEnd) X(glNewList) \
 X(glEndList) X(glCallList) X(glCallLists) X(glClear) X(glDrawArrays) \
 X(glDrawElements) X(glDrawRangeElements) X(glMultiDrawArrays) X(glMultiDrawElements) X(glEvalMesh1) \
 X(glEvalMesh2) X(glRectd) X(glRectf) X(glRecti) X(glRects) \
 X(glRectdv) X(glRectfv) X(glRectiv) X(glRectsv) X(glBitmap) \
 X(glDrawPixels) X(glXMakeCurrent) X(glXMakeContextCurrent) X(glXDestroyContext) X(glXSwapBuffers) \
 X(glXCreateWindow) X(glXDestroyWindow) X(glXQueryDrawable)
static __GLXextFuncPtr wrapper(const char *name)
{
    static const struct { const char *name; __GLXextFuncPtr fn; } entries[] = {
#define ENTRY(name) {#name, (__GLXextFuncPtr)name},
        WRAPPERS(ENTRY)
#undef ENTRY
    };
    for (size_t i = 0; i < sizeof(entries)/sizeof(entries[0]); ++i)
        if (!strcmp(entries[i].name, name)) return entries[i].fn;
    return NULL;
}
__GLXextFuncPtr glXGetProcAddressARB(const GLubyte *name)
{
    API(); __GLXextFuncPtr fn = wrapper((const char *)name);
    return fn ? fn : r_glXGetProcAddressARB(name);
}
__GLXextFuncPtr glXGetProcAddress(const GLubyte *name) { return glXGetProcAddressARB(name); }
__eglMustCastToProperFunctionPointerType eglGetProcAddress(const char *name)
{
    API(); __GLXextFuncPtr fn = wrapper(name);
    return fn ? (__eglMustCastToProperFunctionPointerType)fn : r_eglGetProcAddress(name);
}
void *dlsym(void *handle, const char *name)
{
    if (config.enabled && !resolving && !native_query) {
        __GLXextFuncPtr fn = wrapper(name);
        if (fn) return (void *)fn;
    }
    return lookup_symbol(handle,name);
}
#pragma GCC visibility pop
