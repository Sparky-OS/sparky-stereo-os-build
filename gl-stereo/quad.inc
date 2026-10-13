/* SPDX-License-Identifier: GPL-2.0-or-later */
typedef struct virtual_config {
    GLXFBConfig native;
    struct virtual_config *next;
} VirtualConfig;
typedef struct stereo_visual {
    XVisualInfo *visual;
    struct stereo_visual *next;
} StereoVisual;
static VirtualConfig *virtual_configs;
static StereoVisual *stereo_visuals;
static int quad_available(Display *d)
{
    return config.enabled && stereo_supported_x11(d) >= 1;
}
static GLXFBConfig native_config(GLXFBConfig config, int *stereo)
{
    *stereo = 0;
    for (VirtualConfig *p = virtual_configs; p; p = p->next)
        if ((GLXFBConfig)p == config) { *stereo = 1; return p->native; }
    return config;
}
static GLXFBConfig virtual_config(GLXFBConfig config)
{
    for (VirtualConfig *p = virtual_configs; p; p = p->next)
        if (p->native == config) return (GLXFBConfig)p;
    VirtualConfig *p = calloc(1,sizeof(*p));
    if (!p) abort();
    p->native = config; p->next = virtual_configs; virtual_configs = p;
    return (GLXFBConfig)p;
}
static void remember_visual(XVisualInfo *v)
{
    if (!v) return;
    StereoVisual *p = calloc(1,sizeof(*p));
    if (!p) abort();
    p->visual = v; p->next = stereo_visuals; stereo_visuals = p;
}
static int stereo_visual(XVisualInfo *v)
{
    for (StereoVisual *p = stereo_visuals; p; p = p->next) if (p->visual == v) return 1;
    return 0;
}
static void remember_quad(GLXContext context, int stereo)
{
    if (!context || !stereo) return;
    pthread_mutex_lock(&state_lock);
    ContextState *p = calloc(1,sizeof(*p));
    if (!p) abort();
    p->context = context; p->quad = 1; p->draw_buffer = GL_BACK; p->read_buffer = GL_BACK_LEFT;
    p->next = contexts; contexts = p;
    pthread_mutex_unlock(&state_lock);
}
XVisualInfo *glXChooseVisual(Display *d, int screen, int *attrs)
{
    API();
    if (!quad_available(d) || !attrs) return r_glXChooseVisual(d,screen,attrs);
    int count = 0, wanted = 0;
    while (attrs[count]) {
        int key = attrs[count++];
        if (key == GLX_STEREO) wanted = 1;
        if (key != GLX_RGBA && key != GLX_DOUBLEBUFFER && key != GLX_STEREO && key != GLX_USE_GL) count++;
    }
    if (!wanted) return r_glXChooseVisual(d,screen,attrs);
    int *mono = malloc((count+1)*sizeof(int));
    if (!mono) return NULL;
    int n = 0;
    for (int i = 0; i < count;) {
        int key = attrs[i++];
        if (key == GLX_STEREO) continue;
        mono[n++] = key;
        if (key != GLX_RGBA && key != GLX_DOUBLEBUFFER && key != GLX_USE_GL) mono[n++] = attrs[i++];
    }
    mono[n] = None;
    XVisualInfo *v = r_glXChooseVisual(d,screen,mono);
    free(mono); remember_visual(v); return v;
}
int glXGetConfig(Display *d, XVisualInfo *v, int attr, int *value)
{
    API(); int result = r_glXGetConfig(d,v,attr,value);
    if (!result && attr == GLX_STEREO && stereo_visual(v)) *value = True;
    return result;
}
GLXFBConfig *glXChooseFBConfig(Display *d, int screen, const int *attrs, int *count)
{
    API();
    int size = 0, wanted = 0;
    if (attrs) while (attrs[size]) { if (attrs[size] == GLX_STEREO && attrs[size+1] == True) wanted = 1; size += 2; }
    if (!wanted || !quad_available(d)) return r_glXChooseFBConfig(d,screen,attrs,count);
    int *mono = malloc((size+1)*sizeof(int));
    if (!mono) { *count = 0; return NULL; }
    memcpy(mono,attrs,(size+1)*sizeof(int));
    for (int i = 0; i < size; i += 2) if (mono[i] == GLX_STEREO) mono[i+1] = False;
    GLXFBConfig *result = r_glXChooseFBConfig(d,screen,mono,count);
    free(mono);
    for (int i = 0; result && i < *count; ++i) result[i] = virtual_config(result[i]);
    return result;
}
GLXFBConfig *glXGetFBConfigs(Display *d, int screen, int *count)
{
    API(); GLXFBConfig *native = r_glXGetFBConfigs(d,screen,count);
    if (!native || !quad_available(d)) return native;
    GLXFBConfig *result = malloc(2*(*count)*sizeof(*result));
    if (!result) return native;
    for (int i = 0; i < *count; ++i) { result[i] = native[i]; result[i+*count] = virtual_config(native[i]); }
    *count *= 2; r_XFree(native); return result;
}
int glXGetFBConfigAttrib(Display *d, GLXFBConfig fb, int attr, int *value)
{
    API(); int stereo;
    int result = r_glXGetFBConfigAttrib(d,native_config(fb,&stereo),attr,value);
    if (!result && attr == GLX_STEREO && stereo) *value = True;
    return result;
}
XVisualInfo *glXGetVisualFromFBConfig(Display *d, GLXFBConfig fb)
{
    API(); int stereo; fb = native_config(fb,&stereo);
    XVisualInfo *v = r_glXGetVisualFromFBConfig(d,fb);
    if (stereo) remember_visual(v);
    return v;
}
GLXContext glXCreateContext(Display *d, XVisualInfo *v, GLXContext share, Bool direct)
{
    API(); GLXContext result = NULL;
    int driver_stereo = 0;
    if (config.enabled && v && !r_glXGetConfig(d,v,GLX_STEREO,&driver_stereo) && driver_stereo) {
        /* Native stereo twins can share a visual ID. Packing belongs to us. */
        int count = 0;
        int attrs[] = {GLX_VISUAL_ID, (int)v->visualid, GLX_STEREO, False,
                       GLX_RENDER_TYPE, GLX_RGBA_BIT, None};
        GLXFBConfig *mono = r_glXChooseFBConfig(d,v->screen,attrs,&count);
        if (mono && count) result = r_glXCreateNewContext(d,mono[0],GLX_RGBA_TYPE,share,direct);
        if (mono) r_XFree(mono);
    }
    if (!result) result = r_glXCreateContext(d,v,share,direct);
    remember_quad(result,stereo_visual(v)); return result;
}
GLXContext glXCreateNewContext(Display *d, GLXFBConfig fb, int type, GLXContext share, Bool direct)
{
    API(); int stereo; fb = native_config(fb,&stereo);
    GLXContext result = r_glXCreateNewContext(d,fb,type,share,direct);
    remember_quad(result,stereo); return result;
}
GLXContext glXCreateContextAttribsARB(Display *d, GLXFBConfig fb, GLXContext share, Bool direct, const int *attrs)
{
    API(); int stereo; fb = native_config(fb,&stereo);
    PFNGLXCREATECONTEXTATTRIBSARBPROC create = (PFNGLXCREATECONTEXTATTRIBSARBPROC)r_glXGetProcAddressARB((const GLubyte *)"glXCreateContextAttribsARB");
    GLXContext result = create(d,fb,share,direct,attrs);
    remember_quad(result,stereo); return result;
}
GLXPbuffer glXCreatePbuffer(Display *d, GLXFBConfig fb, const int *attrs)
{
    API(); int stereo; return r_glXCreatePbuffer(d,native_config(fb,&stereo),attrs);
}
GLXPixmap glXCreatePixmap(Display *d, GLXFBConfig fb, Pixmap pixmap, const int *attrs)
{
    API(); int stereo; return r_glXCreatePixmap(d,native_config(fb,&stereo),pixmap,attrs);
}
int XFree(void *ptr)
{
    API(); StereoVisual **p = &stereo_visuals;
    while (*p && (*p)->visual != ptr) p = &(*p)->next;
    if (*p) { StereoVisual *old = *p; *p = old->next; free(old); }
    return r_XFree(ptr);
}
static int quad_default(void)
{
    if (!current || !current->quad) return 0;
    GLint fb; r_glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING,&fb); return fb == 0;
}
static GLenum mono_buffer(GLenum buffer)
{
    if (buffer == GL_BACK_RIGHT) return GL_BACK_LEFT;
    if (buffer == GL_FRONT_RIGHT) return GL_FRONT_LEFT;
    if (buffer == GL_RIGHT || buffer == GL_LEFT) return GL_FRONT_AND_BACK;
    return buffer;
}
void glDrawBuffer(GLenum buffer)
{
    API();
    if (quad_default()) { current->draw_buffer = buffer; r_glDrawBuffer(mono_buffer(buffer)); }
    else r_glDrawBuffer(buffer);
}
void glDrawBuffers(GLsizei count, const GLenum *buffers)
{
    API();
    if (quad_default() && count == 1) glDrawBuffer(buffers[0]);
    else r_glDrawBuffers(count,buffers);
}
void glReadBuffer(GLenum buffer)
{
    API(); GLint fb; r_glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING,&fb);
    if (current && current->quad && !fb) { current->read_buffer = buffer; r_glReadBuffer(mono_buffer(buffer)); }
    else r_glReadBuffer(buffer);
}
void glReadPixels(GLint x, GLint y, GLsizei width, GLsizei height, GLenum format, GLenum type, void *pixels)
{
    API(); GLint fb; r_glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING,&fb);
    if (current && !current->quad && !fb) warn_once(64,"glReadPixels reads the logical left view once");
    if (current && current->quad && current->window && !fb &&
        (current->read_buffer == GL_BACK_RIGHT || current->read_buffer == GL_FRONT_RIGHT || current->read_buffer == GL_RIGHT)) x += current->window->width;
    native_query++; r_glReadPixels(x,y,width,height,format,type,pixels); native_query--;
}
static int virtual_query(GLenum name, GLint *value)
{
    if (!current || !current->quad) return 0;
    if (name == GL_STEREO) { *value = GL_TRUE; return 1; }
    if (name == GL_DRAW_BUFFER && quad_default()) { *value = current->draw_buffer; return 1; }
    GLint fb; r_glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING,&fb);
    if (name == GL_READ_BUFFER && !fb) { *value = current->read_buffer; return 1; }
    return 0;
}
void glGetIntegerv(GLenum name, GLint *value) { API(); if (!virtual_query(name,value)) r_glGetIntegerv(name,value); }
void glGetBooleanv(GLenum name, GLboolean *value) { API(); GLint v; if (virtual_query(name,&v)) *value = !!v; else r_glGetBooleanv(name,value); }
void glGetDoublev(GLenum name, GLdouble *value) { API(); GLint v; if (virtual_query(name,&v)) *value = v; else r_glGetDoublev(name,value); }
void glGetFloatv(GLenum name, GLfloat *value) { API(); GLint v; if (virtual_query(name,&v)) *value = v; else r_glGetFloatv(name,value); }

void glBlitFramebuffer(GLint sx0, GLint sy0, GLint sx1, GLint sy1,
                       GLint dx0, GLint dy0, GLint dx1, GLint dy1, GLbitfield mask, GLenum filter)
{
    API(); native_query++;
    if (quad_default() && current->window) {
        DrawState saved; save_draw(&saved);
        for (int eye = 0; eye < 2; ++eye) if (selected_eye(eye)) {
            set_eye(&saved,eye);
            int offset = eye*current->window->width;
            r_glBlitFramebuffer(sx0,sy0,sx1,sy1,dx0+offset,dy0,dx1+offset,dy1,mask,filter);
        }
        restore_draw(&saved);
    } else r_glBlitFramebuffer(sx0,sy0,sx1,sy1,dx0,dy0,dx1,dy1,mask,filter);
    native_query--;
}
