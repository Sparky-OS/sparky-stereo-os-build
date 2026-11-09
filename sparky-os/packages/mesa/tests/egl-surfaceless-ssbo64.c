// SPDX-License-Identifier: GPL-2.0-or-later
// A compute shader writes with a 64-bit atomic into one storage buffer and reads another, and declares a third block (the highest
// binding) that it never reads (ORDER 486, patch 0035). zink numbers the storage buffers of a shader from the last binding down,
// so the unread block is index 0, the lowest used index is 1, and the 32-bit view of the buffers started at binding 1 while
// the 64-bit view started at binding 0: the atomics went to the wrong buffer and nothing changed in the right one.
// Build: cc -O2 -Wall -Wextra -Werror egl-surfaceless-ssbo64.c -lEGL -lGL; run it on zink (MESA_LOADER_DRIVER_OVERRIDE=zink)
// and on any other driver. Exit 0 and "PASS" when the four 64-bit atomicMin results and the untouched read-only buffers are right.
#define GL_GLEXT_PROTOTYPES
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GL/gl.h>
#include <GL/glext.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static const char *src =
    "#version 450\n#extension GL_ARB_gpu_shader_int64 : require\n#extension GL_NV_shader_atomic_int64 : enable\n"
    "layout(local_size_x = 64) in;\n"
    "layout(std430, binding = 1) buffer F { uint64_t framebuffer[]; };\n"
    "struct Batch { float a, b, c, d, e, f; int numPoints; int firstPoint; };\n"
    "layout(std430, binding = 2) readonly buffer B { Batch batches[]; };\n"
    "layout(std430, binding = 3) readonly buffer X { uint unused[]; };\n"
    "void main() {\n"
    "    uint g = gl_WorkGroupID.x;\n"
    "    if (gl_LocalInvocationID.x == 0u) atomicMin(framebuffer[g], uint64_t(batches[g].numPoints) + 1000ul * uint64_t(g + 1u));\n"
    "}\n";

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
    GLuint sh = glCreateShader(GL_COMPUTE_SHADER);
    glShaderSource(sh, 1, &src, NULL);
    glCompileShader(sh);
    GLint ok;
    glGetShaderiv(sh, GL_COMPILE_STATUS, &ok);
    if (!ok) { char log[2048]; glGetShaderInfoLog(sh, sizeof log, NULL, log); printf("FAIL: compile: %s\n", log); return 2; }
    GLuint p = glCreateProgram();
    glAttachShader(p, sh);
    glLinkProgram(p);
    glUseProgram(p);
    enum { N = 4 };
    struct { float f[6]; int numPoints, firstPoint; } batches[N];
    uint32_t values[N] = {1, 2, 3, 4};  // bound at 3, declared by the shader and never read
    uint64_t fb[N] = {~0ull, ~0ull, ~0ull, ~0ull};
    memset(batches, 0, sizeof batches);
    for (int i = 0; i < N; i++) batches[i].numPoints = 10 * (i + 1);
    GLuint b[3];
    glGenBuffers(3, b);
    glBindBuffer(GL_SHADER_STORAGE_BUFFER, b[0]); glBufferData(GL_SHADER_STORAGE_BUFFER, sizeof batches, batches, GL_DYNAMIC_COPY);
    glBindBuffer(GL_SHADER_STORAGE_BUFFER, b[1]); glBufferData(GL_SHADER_STORAGE_BUFFER, sizeof values, values, GL_DYNAMIC_COPY);
    glBindBuffer(GL_SHADER_STORAGE_BUFFER, b[2]); glBufferData(GL_SHADER_STORAGE_BUFFER, sizeof fb, fb, GL_DYNAMIC_COPY);
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 2, b[0]);
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 3, b[1]);
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, b[2]);
    glDispatchCompute(N, 1, 1);
    glMemoryBarrier(GL_ALL_BARRIER_BITS);
    uint64_t out[N]; uint32_t v2[N];
    glBindBuffer(GL_SHADER_STORAGE_BUFFER, b[2]); glGetBufferSubData(GL_SHADER_STORAGE_BUFFER, 0, sizeof out, out);
    glBindBuffer(GL_SHADER_STORAGE_BUFFER, b[1]); glGetBufferSubData(GL_SHADER_STORAGE_BUFFER, 0, sizeof v2, v2);
    int bad = 0;
    for (int i = 0; i < N; i++) {
        uint64_t want = (uint64_t)batches[i].numPoints + 1000ull * (i + 1);
        printf("entry %d = %llu (want %llu)\n", i, (unsigned long long)out[i], (unsigned long long)want);
        bad += out[i] != want;
    }
    bad += memcmp(v2, values, sizeof v2) != 0;
    puts(bad ? "FAIL" : "PASS");
    return bad ? 1 : 0;
}
