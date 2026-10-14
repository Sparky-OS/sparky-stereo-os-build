/* SPDX-License-Identifier: GPL-2.0-or-later */
#define _GNU_SOURCE
#define GL_GLEXT_PROTOTYPES
#include <GL/gl.h>
#include <GL/glx.h>
#include <dlfcn.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

/* Test oracle: one ordinary window, one camera, no duplicated draws or
 * window virtualization. Mesa builds a shifted frustum and translates the
 * eye. This intentionally does not use the layer's clip-row calculation. */
static void *next(const char *name)
{
    void *(*lookup)(void *,const char *)=dlvsym(RTLD_NEXT,"dlsym","GLIBC_2.2.5");
    return lookup(RTLD_NEXT,name);
}
static _Thread_local int compiling, nested;
typedef struct { GLdouble projection[16]; GLint mode, program, location; int changed; } Camera;
static int canonical(const GLfloat *p)
{
    const int zero[]={1,2,3,4,6,7};
    for (unsigned i=0;i<sizeof(zero)/sizeof(*zero);i++) if (fabs(p[zero[i]])>1e-6) return 0;
    return p[0]>0 && p[5]>0 && p[10]<=-1 && p[14]+p[10]*p[15]<0 && fabs(p[11]+1)<1e-6;
}
static void begin_camera(Camera *camera)
{
    memset(camera,0,sizeof(*camera)); camera->location=-1;
    if (compiling || nested++) return;
    glGetIntegerv(GL_CURRENT_PROGRAM,&camera->program);
    if (camera->program) {
        GLint count, length;
        glGetProgramiv(camera->program,GL_ACTIVE_UNIFORMS,&count);
        glGetProgramiv(camera->program,GL_ACTIVE_UNIFORM_MAX_LENGTH,&length);
        if (length<=0 || length>65536) return;
        char *name=malloc(length);
        for (int i=0;i<count;i++) {
            GLint size; GLenum type; GLfloat value[16];
            glGetActiveUniform(camera->program,i,length,NULL,&size,&type,name);
            if (type!=GL_FLOAT_MAT4 || size!=1) continue;
            GLint location=glGetUniformLocation(camera->program,name);
            if (location<0) continue;
            glGetUniformfv(camera->program,location,value);
            if (!canonical(value)) continue;
            if (camera->location>=0) { camera->location=-1; break; }
            camera->location=location;
            for (int j=0;j<16;j++) camera->projection[j]=value[j];
        }
        free(name);
        if (camera->location<0) return;
    } else {
        glGetDoublev(GL_PROJECTION_MATRIX,camera->projection);
        GLfloat value[16]; for (int i=0;i<16;i++) value[i]=camera->projection[i];
        if (!canonical(value)) return;
    }
    const GLdouble *p=camera->projection;
    double b=p[14]+p[10]*p[15];
    double near=b/(p[10]-1), far=b/(p[10]+1);
    if (!isfinite(far) || !(near>0 && far>near)) return;
    double convergence=getenv("REFERENCE_CONVERGENCE") ? atof(getenv("REFERENCE_CONVERGENCE")) : 5*near;
    double percent=getenv("REFERENCE_SEPARATION") ? atof(getenv("REFERENCE_SEPARATION")) : 2;
    double half_eye=convergence*percent/(100*p[0]);
    if (getenv("REFERENCE_EYE") && !strcmp(getenv("REFERENCE_EYE"),"right")) half_eye=-half_eye;
    double offset=half_eye*near/convergence;
    glGetIntegerv(GL_MATRIX_MODE,&camera->mode);
    glMatrixMode(GL_PROJECTION); glPushMatrix(); glLoadIdentity();
    glFrustum(near*(p[8]-1)/p[0]+offset,near*(p[8]+1)/p[0]+offset,
              near*(p[9]-1)/p[5],near*(p[9]+1)/p[5],near,far);
    glTranslated(half_eye,0,0);
    glTranslated((p[12]+p[8]*p[15])/p[0],(p[13]+p[9]*p[15])/p[5],-p[15]);
    if (camera->program) {
        GLfloat value[16]; glGetFloatv(GL_PROJECTION_MATRIX,value);
        glUniformMatrix4fv(camera->location,1,GL_FALSE,value);
        glPopMatrix();
    }
    glMatrixMode(camera->mode);
    camera->changed=1;
}
static void end_camera(const Camera *camera)
{
    if (compiling) return;
    --nested;
    if (!camera->changed) return;
    if (camera->program) {
        GLfloat value[16]; for (int i=0;i<16;i++) value[i]=camera->projection[i];
        glUniformMatrix4fv(camera->location,1,GL_FALSE,value);
    } else {
        GLint mode; glGetIntegerv(GL_MATRIX_MODE,&mode);
        glMatrixMode(GL_PROJECTION); glPopMatrix(); glMatrixMode(mode);
    }
}
#define SINGLE(name,args,callargs) \
void name args { static __typeof__(&name) real; if (!real) real=next(#name); Camera c; begin_camera(&c); real callargs; end_camera(&c); }
static _Thread_local Camera immediate;
static _Thread_local GLuint primitive;
void glBegin(GLenum mode)
{
    static void (*real)(GLenum); if (!real) real=next("glBegin");
    if (!compiling && getenv("REFERENCE_LIST_PRIMITIVES")) {
        primitive=glGenLists(1);
        void (*list)(GLuint,GLenum)=next("glNewList");list(primitive,GL_COMPILE);
    } else begin_camera(&immediate);
    real(mode);
}
void glEnd(void)
{
    static void (*real)(void); if (!real) real=next("glEnd");
    real();
    if (primitive) {
        void (*end)(void)=next("glEndList");end();
        GLuint list=primitive;primitive=0;glCallList(list);glDeleteLists(list,1);
    } else end_camera(&immediate);
}
void glNewList(GLuint list,GLenum mode)
{
    static void (*real)(GLuint,GLenum); if (!real) real=next("glNewList");
    compiling=1; real(list,mode);
}
void glEndList(void)
{
    static void (*real)(void); if (!real) real=next("glEndList");
    real(); compiling=0;
}
SINGLE(glCallList,(GLuint list),(list))
SINGLE(glCallLists,(GLsizei n,GLenum type,const void *lists),(n,type,lists))
SINGLE(glDrawArrays,(GLenum mode,GLint first,GLsizei count),(mode,first,count))
SINGLE(glDrawElements,(GLenum mode,GLsizei count,GLenum type,const void *indices),(mode,count,type,indices))
SINGLE(glDrawRangeElements,(GLenum mode,GLuint start,GLuint end,GLsizei count,GLenum type,const void *indices),(mode,start,end,count,type,indices))
SINGLE(glMultiDrawArrays,(GLenum mode,const GLint *first,const GLsizei *count,GLsizei n),(mode,first,count,n))
SINGLE(glMultiDrawElements,(GLenum mode,const GLsizei *count,GLenum type,const void *const *indices,GLsizei n),(mode,count,type,indices,n))
SINGLE(glEvalMesh1,(GLenum mode,GLint i1,GLint i2),(mode,i1,i2))
SINGLE(glEvalMesh2,(GLenum mode,GLint i1,GLint i2,GLint j1,GLint j2),(mode,i1,i2,j1,j2))

/* Replay controls obtain entry points through GLX instead of ELF symbols. */
static void *reference_entry(const char *name)
{
#define ENTRY(function) if (!strcmp((const char *)name,#function)) return (void *)function;
    ENTRY(glXGetProcAddress) ENTRY(glXGetProcAddressARB)
    ENTRY(glBegin) ENTRY(glEnd) ENTRY(glNewList) ENTRY(glEndList)
    ENTRY(glCallList) ENTRY(glCallLists) ENTRY(glDrawArrays) ENTRY(glDrawElements)
    ENTRY(glDrawRangeElements) ENTRY(glMultiDrawArrays) ENTRY(glMultiDrawElements)
    ENTRY(glEvalMesh1) ENTRY(glEvalMesh2)
#undef ENTRY
    return NULL;
}
void *dlsym(void *handle,const char *name)
{
    void *entry=reference_entry(name);
    if (entry) return entry;
    void *(*lookup)(void *,const char *)=dlvsym(RTLD_NEXT,"dlsym","GLIBC_2.2.5");
    return lookup(handle,name);
}
__GLXextFuncPtr glXGetProcAddress(const GLubyte *name)
{
    void *entry=reference_entry((const char *)name);
    if (entry) return (__GLXextFuncPtr)entry;
    __GLXextFuncPtr (*real)(const GLubyte *)=next("glXGetProcAddress");
    return real(name);
}
__GLXextFuncPtr glXGetProcAddressARB(const GLubyte *name) { return glXGetProcAddress(name); }
