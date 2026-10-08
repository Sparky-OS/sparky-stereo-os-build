/* Test aid for Kubrick (not part of the patch).
 * - glFinish() before every eglSwapBuffers (the flush Mesa's multiview swap packs without, found by the Qt lane)
 * - logs, for the last paintGL pass before swap number FREEZE_AT: the viewport, the matrix glGetDoublev(GL_MODELVIEW_MATRIX)
 *   returns for the cube, every glTranslatef (cube position, then the cubies' centres) and the projection matrix
 * - at swap FREEZE_AT writes them to GEOM_FILE and then sleeps FREEZE_SECONDS, so the capture shows exactly that frame. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
typedef unsigned int GLenum; typedef int GLint; typedef int GLsizei; typedef double GLdouble; typedef float GLfloat; typedef unsigned int GLbitfield;
#define GL_MODELVIEW_MATRIX 0x0BA6
#define GL_PROJECTION_MATRIX 0x0BA7
static char buf[1 << 20]; static int blen;
static double mv[16], proj[16]; static int vp[4];
static int swaps, nmv; static int cnt[8]; static int moving, in_cubies;  /* per pass: glMatrixMode, glMultMatrixd, glPushMatrix, glPopMatrix, glLoadMatrixd, glFrustum */
static void *next(const char *n) { return dlsym(RTLD_NEXT, n); }
void glClear(GLbitfield m) { static void (*r)(GLbitfield); if (!r) r = next("glClear"); blen = 0; nmv = 0; moving = 0; in_cubies = 0; memset(cnt, 0, sizeof cnt); r(m); }
void glMatrixMode(GLenum m) { static void (*r)(GLenum); if (!r) r = next("glMatrixMode"); cnt[0]++; r(m); }
void glMultMatrixd(const GLdouble *m) { static void (*r)(const GLdouble *); if (!r) r = next("glMultMatrixd"); cnt[1]++; r(m); }
void glPushMatrix(void) { static void (*r)(void); if (!r) r = next("glPushMatrix"); cnt[2]++; r(); }
void glPopMatrix(void) { static void (*r)(void); if (!r) r = next("glPopMatrix"); cnt[3]++; r(); }
void glLoadMatrixd(const GLdouble *m) { static void (*r)(const GLdouble *); if (!r) r = next("glLoadMatrixd"); cnt[4]++; r(m); }
void glFrustum(GLdouble a, GLdouble b, GLdouble c, GLdouble d, GLdouble e, GLdouble f) { static void (*r)(GLdouble,GLdouble,GLdouble,GLdouble,GLdouble,GLdouble); if (!r) r = next("glFrustum"); cnt[5]++; r(a,b,c,d,e,f); }
void glViewport(GLint x, GLint y, GLsizei w, GLsizei h) { static void (*r)(GLint,GLint,GLsizei,GLsizei); if (!r) r = next("glViewport"); if (getenv("VP_LOG") && (vp[2]!=w||vp[3]!=h)) fprintf(stderr, "VIEWPORT %d %d\n", w, h); vp[0]=x;vp[1]=y;vp[2]=w;vp[3]=h; r(x,y,w,h); }
void glTranslatef(GLfloat x, GLfloat y, GLfloat z) { static void (*r)(GLfloat,GLfloat,GLfloat); if (!r) r = next("glTranslatef");
    if (z < -4.9999f && z > -5.0001f) in_cubies = 0;
    if (blen < (1 << 20) - 100) blen += snprintf(buf + blen, 100, "T %.6f %.6f %.6f\n", x, y, z); r(x, y, z); }
void glRotatef(GLfloat a, GLfloat x, GLfloat y, GLfloat z) { static void (*r)(GLfloat,GLfloat,GLfloat,GLfloat); if (!r) r = next("glRotatef");
    if (in_cubies) moving = 1;
    if (blen < (1 << 20) - 100) blen += snprintf(buf + blen, 100, "R %.6f %.3f %.3f %.3f\n", a, x, y, z); r(a, x, y, z); }
void glGetDoublev(GLenum p, GLdouble *d) { static void (*r)(GLenum, GLdouble *); if (!r) r = next("glGetDoublev"); r(p, d);
    if (p == GL_MODELVIEW_MATRIX && blen < (1 << 20) - 400) { blen += snprintf(buf + blen, 400, "M"); for (int i = 0; i < 16; i++) blen += snprintf(buf + blen, 40, " %.9f", d[i]); blen += snprintf(buf + blen, 4, "\n"); memcpy(mv, d, sizeof mv); nmv++; in_cubies = (nmv % 2 == 0); }
    if (p == GL_PROJECTION_MATRIX) memcpy(proj, d, sizeof proj); }
typedef unsigned int EGLBoolean;
static EGLBoolean swap_common(const char *name, void *dpy, void *surf)
{
    EGLBoolean (*real)(void *, void *) = dlsym(RTLD_NEXT, name); static void (*finish)(void);
    if (!finish) finish = dlsym(RTLD_DEFAULT, "glFinish");
    if (finish && !getenv("NO_FINISH")) finish();
    EGLBoolean ret = 0; if (real) real(dpy, surf);
    int at = getenv("FREEZE_AT") ? atoi(getenv("FREEZE_AT")) : 0;
    /* count the swaps of each surface and freeze only in the swap of the surface with the most (the 3D area's: a top-level that
       is not the 3D area swaps rarely), so that the frame left on screen is the frame the log describes */
    static void *seen[8]; static int nseen[8]; int k = 0; while (k < 7 && seen[k] && seen[k] != surf) k++; seen[k] = surf; nseen[k]++;
    int mx = 0; for (int i = 0; i < 8; i++) if (nseen[i] > mx) mx = nseen[i];
    if (nseen[k] < mx) return ret;
    swaps = nseen[k];
    if (at && getenv("GEOM_FILE") && (swaps >= at) && !(getenv("STATIC_ONLY") && (moving || nmv == 0))) {
        FILE *f = fopen(getenv("GEOM_FILE"), "w");
        if (f) { fprintf(f, "VIEWPORT %d %d %d %d\nPROJ", vp[0], vp[1], vp[2], vp[3]); for (int i = 0; i < 16; i++) fprintf(f, " %.9f", proj[i]); fprintf(f, "\n"); fprintf(f, "COUNTS matrixmode %d multmatrixd %d pushmatrix %d popmatrix %d loadmatrixd %d frustum %d\n", cnt[0], cnt[1], cnt[2], cnt[3], cnt[4], cnt[5]); fwrite(buf, 1, blen, f); fclose(f); }
        sleep(getenv("FREEZE_SECONDS") ? atoi(getenv("FREEZE_SECONDS")) : 10);
    }
    return ret;
}
EGLBoolean eglSwapBuffers(void *dpy, void *surf) { return swap_common("eglSwapBuffers", dpy, surf); }
void glXSwapBuffers(void *dpy, unsigned long surf) { swap_common("glXSwapBuffers", dpy, (void *)surf); }

/* Deterministic randomness for same-state comparisons (DETERMINISTIC=1): the same stream on every run. */
#include <sys/types.h>
#include <errno.h>
static unsigned long long seed_state = 88172645463325252ULL;
static void fill(void *p, size_t n) { unsigned char *c = p; while (n--) { seed_state ^= seed_state << 13; seed_state ^= seed_state >> 7; seed_state ^= seed_state << 17; *c++ = (unsigned char)(seed_state >> 24); } }
int getentropy(void *p, size_t n) { static int (*r)(void *, size_t); if (getenv("DETERMINISTIC")) { fill(p, n); return 0; } if (!r) r = next("getentropy"); return r(p, n); }
ssize_t getrandom(void *p, size_t n, unsigned int fl) { static ssize_t (*r)(void *, size_t, unsigned int); if (getenv("DETERMINISTIC")) { fill(p, n); return n; } if (!r) r = next("getrandom"); return r(p, n, fl); }
