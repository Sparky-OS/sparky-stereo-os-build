/* Test aid for the KAlgebra and Kalzium proofs (not part of the patches).
 * - glFinish() before every swap (glXSwapBuffers / eglSwapBuffers)
 * - per paint pass (reset at glClear): the viewport and every 4x4 matrix uniform (glUniformMatrix4fv), written to GEOM_FILE at swap
 *   number FREEZE_AT (0 = off), after which the swap sleeps FREEZE_SECONDS so a capture shows that frame. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <math.h>
typedef unsigned int GLenum; typedef int GLint; typedef int GLsizei; typedef float GLfloat; typedef unsigned int GLbitfield; typedef unsigned char GLboolean;
#define NRING 8
static char buf[1 << 16], ring[NRING][1 << 16], pring[4][1 << 16]; static int plen[4], ppos, projective; static int blen, ringlen[NRING], ringpos, vp[4], swaps;
static void *next(const char *n) { return dlsym(RTLD_NEXT, n); }
void glClear(GLbitfield m) { static void (*r)(GLbitfield); if (!r) r = next("glClear"); if (m & 0x4000) { if (projective && blen) { memcpy(pring[ppos % 4], buf, blen); plen[ppos % 4] = blen; ppos++; } projective = 0; if (blen) { memcpy(ring[ringpos % NRING], buf, blen); ringlen[ringpos % NRING] = blen; ringpos++; } blen = 0; } r(m); }
void glViewport(GLint x, GLint y, GLsizei w, GLsizei h) { static void (*r)(GLint,GLint,GLsizei,GLsizei); if (!r) r = next("glViewport"); vp[0]=x;vp[1]=y;vp[2]=w;vp[3]=h; r(x,y,w,h); }
void shim_log_matrix(const GLfloat *v);
void glUniformMatrix4fv(GLint loc, GLsizei n, GLboolean tr, const GLfloat *v) { static void (*r)(GLint,GLsizei,GLboolean,const GLfloat *); if (!r) r = next("glUniformMatrix4fv");
    if (fabsf(v[3]) + fabsf(v[7]) + fabsf(v[11]) > 1e-6f) projective = 1;
    if (blen < (1 << 16) - 600) { blen += snprintf(buf + blen, 40, "U %d %d", loc, tr); for (int i = 0; i < 16; i++) blen += snprintf(buf + blen, 24, " %.9g", v[i]); blen += snprintf(buf + blen, 4, "\n"); } if (loc != -1) r(loc, n, tr, v); }
static void dump(FILE *f)
{
    fprintf(f, "VIEWPORT %d %d %d %d\n", vp[0], vp[1], vp[2], vp[3]);
    for (int i = ppos > 4 ? ppos - 4 : 0; i < ppos; i++) { fprintf(f, "PASS p%d\n", i); fwrite(pring[i % 4], 1, plen[i % 4], f); }
    for (int i = ringpos > NRING ? ringpos - NRING : 0; i < ringpos; i++) { fprintf(f, "PASS %d\n", i); fwrite(ring[i % NRING], 1, ringlen[i % NRING], f); }
    fprintf(f, "PASS %d\n", ringpos); fwrite(buf, 1, blen, f); fclose(f);
}
static void swap_common(const char *name, void *dpy, void *surf)
{
    void (*real)(void *, void *) = dlsym(RTLD_NEXT, name); static void (*finish)(void);
    if (!finish) finish = dlsym(RTLD_DEFAULT, "glFinish");
    if (finish && !getenv("NO_FINISH")) finish();
    if (real) real(dpy, surf);
    if (getenv("GEOM_EVERY") && getenv("GEOM_FILE") && (blen || ringpos)) {
        FILE *f = fopen(getenv("GEOM_FILE"), "w");
        if (f) { dump(f); }
    }
    int at = getenv("FREEZE_AT") ? atoi(getenv("FREEZE_AT")) : 0;
    if (at && getenv("GEOM_FILE") && ++swaps == at) {
        FILE *f = fopen(getenv("GEOM_FILE"), "w");
        if (f) { dump(f); }
        sleep(getenv("FREEZE_SECONDS") ? atoi(getenv("FREEZE_SECONDS")) : 10);
    }
}
void eglSwapBuffers(void *dpy, void *surf) { swap_common("eglSwapBuffers", dpy, surf); }
void glXSwapBuffers(void *dpy, unsigned long surf) { swap_common("glXSwapBuffers", dpy, (void *)surf); }

/* Qt resolves its GL functions with *GetProcAddress, which bypasses the symbols above: hand out ours for the ones we log. */
static void *mine(const char *n)
{
    if (!strcmp(n, "glUniformMatrix4fv")) return (void *)glUniformMatrix4fv;
    if (!strcmp(n, "glClear")) return (void *)glClear;
    if (!strcmp(n, "glViewport")) return (void *)glViewport;
    return NULL;
}
void *glXGetProcAddress(const unsigned char *n) { static void *(*r)(const unsigned char *); if (!r) r = next("glXGetProcAddress"); void *m = mine((const char *)n); return m ? m : r(n); }
void *glXGetProcAddressARB(const unsigned char *n) { static void *(*r)(const unsigned char *); if (!r) r = next("glXGetProcAddressARB"); void *m = mine((const char *)n); return m ? m : r(n); }
void *eglGetProcAddress(const char *n) { static void *(*r)(const char *); if (!r) r = next("eglGetProcAddress"); void *m = mine(n); return m ? m : r(n); }

/* the plain-C logging entry for the C++ wrapper in qt-uniform-shim.cpp */
void shim_log_matrix(const GLfloat *v) { glUniformMatrix4fv(-1, 1, 0, v); }
