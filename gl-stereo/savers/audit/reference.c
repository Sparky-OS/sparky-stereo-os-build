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
typedef struct { GLdouble projection[16], inverse[16]; GLint mode, program, location; int changed, through_modelview; } Camera;
/* M = P A with P a canonical perspective and A a rotation, uniform scale and
 * translation: P from M (column-major), 0 when M is not of that form. Row r of
 * M is (m[r], m[4+r], m[8+r], m[12+r]); row 3 of M is minus row 2 of A. */
static int modelview_perspective(const GLdouble *m, GLdouble *p)
{
    double a2[4], r0[4], r1[4], r2[4];
    for (int c=0;c<4;c++) { a2[c]=-m[4*c+3]; r0[c]=m[4*c]; r1[c]=m[4*c+1]; r2[c]=m[4*c+2]; }
    double s2=a2[0]*a2[0]+a2[1]*a2[1]+a2[2]*a2[2];
    if (!(s2>1e-12)) return 0;
    double p10=(r2[0]*a2[0]+r2[1]*a2[1]+r2[2]*a2[2])/s2;
    double p8=(r0[0]*a2[0]+r0[1]*a2[1]+r0[2]*a2[2])/s2, p9=(r1[0]*a2[0]+r1[1]*a2[1]+r1[2]*a2[2])/s2;
    double a0[3], a1[3], n0=0, n1=0;
    for (int c=0;c<3;c++) { a0[c]=r0[c]-p8*a2[c]; a1[c]=r1[c]-p9*a2[c]; n0+=a0[c]*a0[c]; n1+=a1[c]*a1[c]; }
    double p0=sqrt(n0/s2), p5=sqrt(n1/s2);
    if (!(p0>0 && p5>0)) return 0;
    /* A's rows: orthogonal, of one length, or this is not a view */
    double d01=0,d02=0,d12=0, rz=0;
    for (int c=0;c<3;c++) { d01+=a0[c]*a1[c]; d02+=a0[c]*a2[c]; d12+=a1[c]*a2[c]; rz+=(r2[c]-p10*a2[c])*(r2[c]-p10*a2[c]); }
    double tolerance=1e-6*s2*(1+p0*p0+p5*p5);
    if (fabs(d01)>tolerance*p0*p5 || fabs(d02)>tolerance*p0 || fabs(d12)>tolerance*p5 || rz>tolerance*(1+p10*p10)) return 0;
    if (fabs(n0/(p0*p0)-s2)>1e-6*s2 || fabs(n1/(p5*p5)-s2)>1e-6*s2) return 0;
    double p14=r2[3]-p10*a2[3];
    memset(p,0,16*sizeof(*p));
    p[0]=p0; p[5]=p5; p[8]=p8; p[9]=p9; p[10]=p10; p[11]=-1; p[14]=p14;
    return 1;
}
/* A general 4x4 inverse (column-major), by cofactors; 0 when singular. */
static int invert(const GLdouble *m, GLdouble *out)
{
    GLdouble inv[16];
    inv[0]=m[5]*m[10]*m[15]-m[5]*m[11]*m[14]-m[9]*m[6]*m[15]+m[9]*m[7]*m[14]+m[13]*m[6]*m[11]-m[13]*m[7]*m[10];
    inv[4]=-m[4]*m[10]*m[15]+m[4]*m[11]*m[14]+m[8]*m[6]*m[15]-m[8]*m[7]*m[14]-m[12]*m[6]*m[11]+m[12]*m[7]*m[10];
    inv[8]=m[4]*m[9]*m[15]-m[4]*m[11]*m[13]-m[8]*m[5]*m[15]+m[8]*m[7]*m[13]+m[12]*m[5]*m[11]-m[12]*m[7]*m[9];
    inv[12]=-m[4]*m[9]*m[14]+m[4]*m[10]*m[13]+m[8]*m[5]*m[14]-m[8]*m[6]*m[13]-m[12]*m[5]*m[10]+m[12]*m[6]*m[9];
    inv[1]=-m[1]*m[10]*m[15]+m[1]*m[11]*m[14]+m[9]*m[2]*m[15]-m[9]*m[3]*m[14]-m[13]*m[2]*m[11]+m[13]*m[3]*m[10];
    inv[5]=m[0]*m[10]*m[15]-m[0]*m[11]*m[14]-m[8]*m[2]*m[15]+m[8]*m[3]*m[14]+m[12]*m[2]*m[11]-m[12]*m[3]*m[10];
    inv[9]=-m[0]*m[9]*m[15]+m[0]*m[11]*m[13]+m[8]*m[1]*m[15]-m[8]*m[3]*m[13]-m[12]*m[1]*m[11]+m[12]*m[3]*m[9];
    inv[13]=m[0]*m[9]*m[14]-m[0]*m[10]*m[13]-m[8]*m[1]*m[14]+m[8]*m[2]*m[13]+m[12]*m[1]*m[10]-m[12]*m[2]*m[9];
    inv[2]=m[1]*m[6]*m[15]-m[1]*m[7]*m[14]-m[5]*m[2]*m[15]+m[5]*m[3]*m[14]+m[13]*m[2]*m[7]-m[13]*m[3]*m[6];
    inv[6]=-m[0]*m[6]*m[15]+m[0]*m[7]*m[14]+m[4]*m[2]*m[15]-m[4]*m[3]*m[14]-m[12]*m[2]*m[7]+m[12]*m[3]*m[6];
    inv[10]=m[0]*m[5]*m[15]-m[0]*m[7]*m[13]-m[4]*m[1]*m[15]+m[4]*m[3]*m[13]+m[12]*m[1]*m[7]-m[12]*m[3]*m[5];
    inv[14]=-m[0]*m[5]*m[14]+m[0]*m[6]*m[13]+m[4]*m[1]*m[14]-m[4]*m[2]*m[13]-m[12]*m[1]*m[6]+m[12]*m[2]*m[5];
    inv[3]=-m[1]*m[6]*m[11]+m[1]*m[7]*m[10]+m[5]*m[2]*m[11]-m[5]*m[3]*m[10]-m[9]*m[2]*m[7]+m[9]*m[3]*m[6];
    inv[7]=m[0]*m[6]*m[11]-m[0]*m[7]*m[10]-m[4]*m[2]*m[11]+m[4]*m[3]*m[10]+m[8]*m[2]*m[7]-m[8]*m[3]*m[6];
    inv[11]=-m[0]*m[5]*m[11]+m[0]*m[7]*m[9]+m[4]*m[1]*m[11]-m[4]*m[3]*m[9]-m[8]*m[1]*m[7]+m[8]*m[3]*m[5];
    inv[15]=m[0]*m[5]*m[10]-m[0]*m[6]*m[9]-m[4]*m[1]*m[10]+m[4]*m[2]*m[9]+m[8]*m[1]*m[6]-m[8]*m[2]*m[5];
    GLdouble det=m[0]*inv[0]+m[1]*inv[4]+m[2]*inv[8]+m[3]*inv[12];
    if (!isfinite(det) || fabs(det)<1e-300) return 0;
    for (int i=0;i<16;i++) out[i]=inv[i]/det;
    return 1;
}
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
        if (!canonical(value)) {
            /* Perspective placed in GL_MODELVIEW under an identity projection
             * (Star Wars): the modelview M is a canonical perspective P times
             * a view A that rotates, translates and scales uniformly. P is
             * recovered from M (its last row is minus A's third row), the
             * eye's camera E is built from P as below, and the projection
             * becomes E times P's inverse, so that with M it gives E times A
             * and the program's modelview stays untouched. */
            for (int i=0;i<16;i++) if (fabs(camera->projection[i]-(i%5==0))>1e-9) return;
            GLdouble m[16];
            glGetDoublev(GL_MODELVIEW_MATRIX,m);
            if (!modelview_perspective(m,camera->projection)) return;
            for (int i=0;i<16;i++) value[i]=camera->projection[i];
            if (!canonical(value) || !invert(camera->projection,camera->inverse)) return;
            camera->through_modelview=1;
        }
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
    if (camera->through_modelview) glMultMatrixd(camera->inverse);
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
