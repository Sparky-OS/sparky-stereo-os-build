// SPDX-License-Identifier: BSD-3-Clause
// LD_PRELOAD shim over vtkOpenGLRenderWindow::GetColorBufferSizes(int*) of Debian's vtk9 9.6.2+ds-3, to find and test
// the cause of VTK's "Failed to get <colour> color buffer size" warnings without rebuilding vtk9. No VTK header: GL is
// reached through glvnd's libOpenGL.so.0, which dispatches to the current context (EGL or GLX).
//   COLOUR_SIZE_SHIM=probe  print the state at each query on stderr, then run VTK's own function (the warnings stay)
//   COLOUR_SIZE_SHIM=fix    the drafted VTK patch's rule: read the draw buffer's attachment type first; with no image
//                           there (GL_NONE) the sizes are 0 and nothing else is queried; otherwise VTK's own function
//   unset                   VTK's own function only
// Build: g++ -O2 -shared -fPIC -o libcolour-size-shim.so shim.cxx -ldl
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>

namespace
{
typedef unsigned int GLenum;
typedef int GLint;
const GLenum kDrawFramebuffer = 0x8CA9, kDrawFramebufferBinding = 0x8CA6, kDrawBuffer = 0x0C01;
const GLenum kFront = 0x0404, kBack = 0x0405, kFrontLeft = 0x0400, kBackLeft = 0x0402, kNone = 0;
const GLenum kObjectType = 0x8CD0;

template <typename F>
F gl(const char* name)
{
  static void* lib = dlopen("libOpenGL.so.0", RTLD_LAZY | RTLD_GLOBAL);
  return lib ? reinterpret_cast<F>(dlsym(lib, name)) : nullptr;
}

void* currentSurface()
{
  void* egl = dlopen("libEGL.so.1", RTLD_LAZY | RTLD_NOLOAD);
  if (!egl)
  {
    return nullptr;
  }
  auto getDisplay = reinterpret_cast<void* (*)()>(dlsym(egl, "eglGetCurrentDisplay"));
  auto getSurface = reinterpret_cast<void* (*)(GLint)>(dlsym(egl, "eglGetCurrentSurface"));
  return (getDisplay && getDisplay() && getSurface) ? getSurface(0x3059 /* EGL_DRAW */) : nullptr;
}

unsigned long currentDrawable()
{
  void* glx = dlopen("libGLX.so.0", RTLD_LAZY | RTLD_NOLOAD);
  auto get = glx ? reinterpret_cast<unsigned long (*)()>(dlsym(glx, "glXGetCurrentDrawable")) : nullptr;
  return get ? get() : 0;
}
}

extern "C" int _ZN21vtkOpenGLRenderWindow19GetColorBufferSizesEPi(void* self, int* rgba)
{
  using Fn = int (*)(void*, int*);
  static Fn vtkOwn = reinterpret_cast<Fn>(dlsym(RTLD_NEXT, "_ZN21vtkOpenGLRenderWindow19GetColorBufferSizesEPi"));
  const char* mode = std::getenv("COLOUR_SIZE_SHIM");
  auto getIntegerv = gl<void (*)(GLenum, GLint*)>("glGetIntegerv");
  auto getAttachment = gl<void (*)(GLenum, GLenum, GLenum, GLint*)>("glGetFramebufferAttachmentParameteriv");
  auto getError = gl<GLenum (*)()>("glGetError");
  if (!mode || !getIntegerv || !getAttachment || !getError || !rgba)
  {
    return vtkOwn(self, rgba);
  }
  GLint binding = -1, drawBuffer = -1;
  getIntegerv(kDrawFramebufferBinding, &binding);
  getIntegerv(kDrawBuffer, &drawBuffer);
  GLenum attachment = static_cast<GLenum>(drawBuffer);
  if (attachment == kFront) attachment = kFrontLeft;
  if (attachment == kBack || attachment == kNone) attachment = kBackLeft;
  while (getError() != 0)
  {
  }
  GLint type = -1;
  getAttachment(kDrawFramebuffer, attachment, kObjectType, &type);
  const GLenum typeError = getError();
  std::fprintf(stderr,
    "colour-size-shim: mode=%s draw framebuffer=%d draw buffer=0x%x attachment=0x%x object type=0x%x (error 0x%x)"
    " egl surface=%p glx drawable=0x%lx\n",
    mode, binding, static_cast<unsigned>(drawBuffer), attachment, static_cast<unsigned>(type), typeError,
    currentSurface(), currentDrawable());
  if (std::strcmp(mode, "fix") == 0 && typeError == 0 && type == static_cast<GLint>(kNone))
  {
    rgba[0] = rgba[1] = rgba[2] = rgba[3] = 0;
    return 0;
  }
  return vtkOwn(self, rgba);
}
