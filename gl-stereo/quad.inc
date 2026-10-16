/* SPDX-License-Identifier: GPL-2.0-or-later */
typedef struct virtual_config {
    GLXFBConfig native;
    struct virtual_config *next;
} VirtualConfig;
typedef struct stereo_visual {
    XVisualInfo *visual;
    VisualID id;
    int screen;
    struct stereo_visual *next;
} StereoVisual;
static VirtualConfig *virtual_configs;
static StereoVisual *stereo_visuals;
static int quad_available(Display *d)
{
    return config.enabled && stereo_supported_x11(d) >= 1;
}
/* With GL_STEREO_DRIVER_VIEWS=1 a driver with stereo configs of its own
 * (Mesa's, also on NVIDIA's Vulkan through zink) gives a program its two views
 * and presents them itself, and the layer provides them only where the driver
 * has none, such as NVIDIA's OpenGL. By default the layer keeps the packing,
 * which its frame stream needs. */
static int driver_views(Display *d, GLXFBConfig *configs, int count)
{
    for (int i = 0; i < count; ++i) {
        int stereo = 0;
        if (!r_glXGetFBConfigAttrib(d,configs[i],GLX_STEREO,&stereo) && stereo) return 1;
    }
    return 0;
}
static void remember_driver_views(GLXContext context)
{
    if (!context) return;
    pthread_mutex_lock(&state_lock);
    ContextState *p = calloc(1,sizeof(*p));
    if (!p) abort();
    p->context = context; p->driver_views = 1;
    p->next = contexts; contexts = p;
    pthread_mutex_unlock(&state_lock);
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
    p->visual = v; p->id = v->visualid; p->screen = v->screen; p->next = stereo_visuals; stereo_visuals = p;
}
static int stereo_visual(XVisualInfo *v)
{
    if (!v) return 0;
    for (StereoVisual *p = stereo_visuals; p; p = p->next)
        if (p->visual == v || (p->id == v->visualid && p->screen == v->screen)) return 1;
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
    XVisualInfo *native = config.driver_views ? r_glXChooseVisual(d,screen,attrs) : NULL;
    if (native) return native;
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
    if (config.driver_views) {
        GLXFBConfig *native = r_glXChooseFBConfig(d,screen,attrs,count);
        if (native && *count > 0) return native;
        if (native) r_XFree(native);
    }
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
    if (!native || !quad_available(d) || (config.driver_views && driver_views(d,native,*count))) return native;
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
    if (config.enabled && v && !r_glXGetConfig(d,v,GLX_STEREO,&driver_stereo) && driver_stereo && config.driver_views) {
        result = r_glXCreateContext(d,v,share,direct);
        remember_driver_views(result);
        return result;
    }
    if (config.enabled && v && driver_stereo) {
        /* Native stereo twins can share a visual ID. Packing belongs to us. */
        int count = 0;
        const int keys[] = {GLX_DOUBLEBUFFER, GLX_LEVEL, GLX_RED_SIZE,
                           GLX_GREEN_SIZE, GLX_BLUE_SIZE, GLX_ALPHA_SIZE,
                           GLX_DEPTH_SIZE, GLX_STENCIL_SIZE, GLX_ACCUM_RED_SIZE,
                           GLX_ACCUM_GREEN_SIZE, GLX_ACCUM_BLUE_SIZE,
                           GLX_ACCUM_ALPHA_SIZE, GLX_AUX_BUFFERS,
                           GLX_SAMPLE_BUFFERS, GLX_SAMPLES};
        int attrs[7 + 2 * (sizeof(keys) / sizeof(keys[0]))];
        int n = 0;
        attrs[n++] = GLX_VISUAL_ID; attrs[n++] = (int)v->visualid;
        attrs[n++] = GLX_STEREO; attrs[n++] = False;
        attrs[n++] = GLX_RENDER_TYPE; attrs[n++] = GLX_RGBA_BIT;
        for (unsigned i = 0; i < sizeof(keys) / sizeof(keys[0]); ++i) {
            int value;
            if (!r_glXGetConfig(d,v,keys[i],&value)) {
                attrs[n++] = keys[i]; attrs[n++] = value;
            }
        }
        attrs[n] = None;
        GLXFBConfig *mono = r_glXChooseFBConfig(d,v->screen,attrs,&count);
        if (mono && count) result = r_glXCreateNewContext(d,mono[0],GLX_RGBA_TYPE,share,direct);
        if (mono) r_XFree(mono);
    }
    if (!result) result = r_glXCreateContext(d,v,share,direct);
    remember_quad(result,stereo_visual(v)); return result;
}
static int driver_stereo_config(Display *d, GLXFBConfig fb)
{
    int stereo = 0;
    return config.enabled && config.driver_views && !r_glXGetFBConfigAttrib(d,fb,GLX_STEREO,&stereo) && stereo;
}
GLXContext glXCreateNewContext(Display *d, GLXFBConfig fb, int type, GLXContext share, Bool direct)
{
    API(); int stereo; fb = native_config(fb,&stereo);
    GLXContext result = r_glXCreateNewContext(d,fb,type,share,direct);
    if (!stereo && driver_stereo_config(d,fb)) remember_driver_views(result);
    else remember_quad(result,stereo);
    return result;
}
GLXContext glXCreateContextAttribsARB(Display *d, GLXFBConfig fb, GLXContext share, Bool direct, const int *attrs)
{
    API(); int stereo; fb = native_config(fb,&stereo);
    PFNGLXCREATECONTEXTATTRIBSARBPROC create = (PFNGLXCREATECONTEXTATTRIBSARBPROC)r_glXGetProcAddressARB((const GLubyte *)"glXCreateContextAttribsARB");
    GLXContext result = create(d,fb,share,direct,attrs);
    if (!stereo && driver_stereo_config(d,fb)) remember_driver_views(result);
    else remember_quad(result,stereo);
    return result;
}
GLXPbuffer glXCreatePbuffer(Display *d, GLXFBConfig fb, const int *attrs)
{
    API(); int stereo; return r_glXCreatePbuffer(d,native_config(fb,&stereo),attrs);
}
GLXPixmap glXCreatePixmap(Display *d, GLXFBConfig fb, Pixmap pixmap, const int *attrs)
{
    API(); int stereo; return r_glXCreatePixmap(d,native_config(fb,&stereo),pixmap,attrs);
}
/* A freed XVisualInfo keeps its visual ID: toolkits free theirs once the
 * window exists and create the context from a copy of the window's visual. */
int XFree(void *ptr)
{
    API();
    for (StereoVisual *p = stereo_visuals; p; p = p->next) if (p->visual == ptr) p->visual = NULL;
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
/* OpenGL ES has one back buffer name for the default framebuffer. */
static void native_draw_buffer(GLenum buffer)
{
    if (current && current->gles) { const GLenum back = buffer == GL_NONE ? GL_NONE : GL_BACK; r_glDrawBuffers(1,&back); }
    else r_glDrawBuffer(mono_buffer(buffer));
}
void glDrawBuffer(GLenum buffer)
{
    API();
    if (quad_default()) { current->draw_buffer = buffer; native_draw_buffer(buffer); }
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
    if (current && current->quad && !fb) {
        current->read_buffer = buffer;
        r_glReadBuffer(current->gles ? (buffer == GL_NONE ? GL_NONE : GL_BACK) : mono_buffer(buffer));
    } else r_glReadBuffer(buffer);
}
/* GL_EXT_multiview_draw_buffers, the OpenGL ES way to name the views of an
 * EGL_EXT_multiview_window surface: on the default framebuffer a location is
 * MULTIVIEW_EXT with the view's index, 0 or 1, or NONE; on a framebuffer
 * object COLOR_ATTACHMENT_EXT with the attachment's index, or NONE. The
 * initial state is view 0, as GL_BACK. Fragment colour zero picks the view,
 * as the layer draws one view at a time. */
#define GL_COLOR_ATTACHMENT_EXT 0x90F0
#define GL_MULTIVIEW_EXT 0x90F1
#define GL_DRAW_BUFFER_EXT 0x0C01
#define GL_READ_BUFFER_EXT 0x0C02
#define GL_MAX_MULTIVIEW_BUFFERS_EXT 0x90F2
static const char multiview_draw_buffers[] = "GL_EXT_multiview_draw_buffers";
static GLenum view_buffer(GLenum location, GLint index)
{
    if (location != GL_MULTIVIEW_EXT || index < 0 || index > 1) return GL_NONE;
    return index ? GL_BACK_RIGHT : GL_BACK_LEFT;
}
void glDrawBuffersIndexedEXT(GLint n, const GLenum *location, const GLint *indices)
{
    API();
    if (n < 1 || !current || !current->quad) return;
    if (quad_default()) { glDrawBuffer(view_buffer(location[0], indices[0])); return; }
    GLenum buffers[16];
    if (n > 16) n = 16;
    for (GLint i = 0; i < n; ++i)
        buffers[i] = location[i] == GL_COLOR_ATTACHMENT_EXT && indices[i] >= 0 ? GL_COLOR_ATTACHMENT0 + (GLenum)indices[i] : GL_NONE;
    r_glDrawBuffers(n, buffers);
}
void glReadBufferIndexedEXT(GLenum location, GLint index)
{
    API();
    if (!current || !current->quad) return;
    GLint fb; r_glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING,&fb);
    if (!fb) glReadBuffer(view_buffer(location, index));
    else r_glReadBuffer(location == GL_COLOR_ATTACHMENT_EXT && index >= 0 ? GL_COLOR_ATTACHMENT0 + (GLenum)index : GL_NONE);
}
/* A pair: the buffer's location and its index. */
static void indexed_buffer(GLenum buffer, GLint fb, GLint *data)
{
    if (!fb && buffer != GL_NONE) { data[0] = GL_MULTIVIEW_EXT; data[1] = buffer == GL_BACK_RIGHT || buffer == GL_FRONT_RIGHT || buffer == GL_RIGHT; }
    else if (fb && buffer >= GL_COLOR_ATTACHMENT0 && buffer < GL_COLOR_ATTACHMENT0 + 32) { data[0] = GL_COLOR_ATTACHMENT_EXT; data[1] = (GLint)(buffer - GL_COLOR_ATTACHMENT0); }
    else { data[0] = GL_NONE; data[1] = 0; }
}
void glGetIntegeri_vEXT(GLenum target, GLuint index, GLint *data)
{
    API();
    if (!current || !current->quad) return;
    if (target == GL_DRAW_BUFFER_EXT) {
        GLint fb, buffer = GL_NONE; r_glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING,&fb);
        if (!fb) buffer = index ? GL_NONE : (GLint)current->draw_buffer;
        else r_glGetIntegerv(GL_DRAW_BUFFER0 + index,&buffer);
        indexed_buffer((GLenum)buffer, fb, data);
    } else if (target == GL_READ_BUFFER_EXT && index == 0) {
        GLint fb, buffer; r_glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING,&fb);
        if (!fb) buffer = (GLint)current->read_buffer; else r_glGetIntegerv(GL_READ_BUFFER,&buffer);
        indexed_buffer((GLenum)buffer, fb, data);
    }
}
const GLubyte *glGetString(GLenum name)
{
    API(); const GLubyte *native = r_glGetString(name);
    if (name != GL_EXTENSIONS || !native || !current || !current->quad || !current->gles || strstr((const char *)native, multiview_draw_buffers)) return native;
    if (!current->extensions) {
        size_t len = strlen((const char *)native);
        current->extensions = malloc(len + sizeof(multiview_draw_buffers) + 1);
        if (!current->extensions) return native;
        memcpy(current->extensions, native, len);
        current->extensions[len] = ' ';
        memcpy(current->extensions + len + 1, multiview_draw_buffers, sizeof(multiview_draw_buffers));
    }
    return (const GLubyte *)current->extensions;
}
const GLubyte *glGetStringi(GLenum name, GLuint index)
{
    API();
    if (name == GL_EXTENSIONS && current && current->quad && current->gles) {
        GLint count = 0; r_glGetIntegerv(GL_NUM_EXTENSIONS,&count);
        if (index == (GLuint)count) return (const GLubyte *)multiview_draw_buffers;
    }
    return r_glGetStringi(name,index);
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
    if (current->gles && name == GL_NUM_EXTENSIONS) { r_glGetIntegerv(name,value); ++*value; return 1; }
    if (current->gles && name == GL_MAX_MULTIVIEW_BUFFERS_EXT) { *value = 2; return 1; }
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
