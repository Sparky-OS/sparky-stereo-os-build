// SPDX-License-Identifier: GPL-2.0-or-later
// ARB_sparse_buffer: a sparse buffer whose size is not a whole number of pages, committed up to its end, keeps what is written to it
// (ORDER 486, patch 0036). zink bound the last block with the buffer's own size, not the block's: NVIDIA's Vulkan driver ignored
// the bind, the pages stayed unbacked and read as zero, and the validation layers reported VUID-VkSparseMemoryBind-resourceOffset-09491.
// Build: cc -O2 -Wall -Wextra -Werror egl-surfaceless-sparse-tail.c -lEGL -lGL; run it on zink and on any other driver.
// Exit 0 and "PASS" when the bytes read back are the bytes written, for a buffer shorter than a page and for one with a partial last page.
#define GL_GLEXT_PROTOTYPES
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GL/gl.h>
#include <GL/glext.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef void (*CommitFn)(GLenum, GLintptr, GLsizeiptr, GLboolean);

static int check(CommitFn commit, GLint page, unsigned size)
{
    GLuint b;
    glGenBuffers(1, &b);
    glBindBuffer(GL_SHADER_STORAGE_BUFFER, b);
    glBufferStorage(GL_SHADER_STORAGE_BUFFER, size, NULL, GL_DYNAMIC_STORAGE_BIT | GL_SPARSE_STORAGE_BIT_ARB);
    // whole pages from the start, then the rest up to the end of the buffer
    GLsizeiptr whole = size / page * page;
    if (whole) commit(GL_SHADER_STORAGE_BUFFER, 0, whole, GL_TRUE);
    if (size > whole) commit(GL_SHADER_STORAGE_BUFFER, whole, size - whole, GL_TRUE);
    uint8_t *in = malloc(size), *out = malloc(size);
    if (!in || !out) return 1;
    for (unsigned i = 0; i < size; i++) in[i] = (uint8_t)(1 + i % 251);
    glBufferSubData(GL_SHADER_STORAGE_BUFFER, 0, size, in);
    glMemoryBarrier(GL_ALL_BARRIER_BITS);
    memset(out, 0, size);
    glGetBufferSubData(GL_SHADER_STORAGE_BUFFER, 0, size, out);
    unsigned bad = 0;
    for (unsigned i = 0; i < size; i++) bad += in[i] != out[i];
    printf("buffer of %u bytes (page %d): %u bytes differ\n", size, page, bad);
    free(in); free(out);
    return bad != 0;
}

int main(void)
{
    EGLDisplay d = eglGetPlatformDisplay(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, NULL);
    EGLint maj, min;
    if (d == EGL_NO_DISPLAY || !eglInitialize(d, &maj, &min)) { puts("FAIL: no display"); return 2; }
    eglBindAPI(EGL_OPENGL_API);
    EGLint ca[] = {EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT, EGL_NONE};
    EGLConfig cfg; EGLint n;
    eglChooseConfig(d, ca, &cfg, 1, &n);
    EGLint xa[] = {EGL_CONTEXT_MAJOR_VERSION, 4, EGL_CONTEXT_MINOR_VERSION, 6, EGL_CONTEXT_OPENGL_PROFILE_MASK, EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT, EGL_NONE};
    EGLContext c = eglCreateContext(d, cfg, EGL_NO_CONTEXT, xa);
    EGLint pa[] = {EGL_WIDTH, 16, EGL_HEIGHT, 16, EGL_NONE};
    EGLSurface s = eglCreatePbufferSurface(d, cfg, pa);
    if (c == EGL_NO_CONTEXT || !eglMakeCurrent(d, s, s, c)) { puts("FAIL: no context"); return 2; }
    printf("renderer: %s\n", glGetString(GL_RENDERER));
    CommitFn commit = (CommitFn)eglGetProcAddress("glBufferPageCommitmentARB");
    GLint page = 0;
    glGetIntegerv(GL_SPARSE_BUFFER_PAGE_SIZE_ARB, &page);
    if (!commit || page <= 0) { puts("SKIP: no ARB_sparse_buffer"); return 77; }
    int bad = check(commit, page, 864);                 // shorter than a page
    bad += check(commit, page, 3 * (unsigned)page + 31424);  // partial last page
    puts(bad ? "FAIL" : "PASS");
    return bad ? 1 : 0;
}
