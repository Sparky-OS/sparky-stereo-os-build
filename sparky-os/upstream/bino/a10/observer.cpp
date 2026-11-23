/* SPDX-License-Identifier: GPL-3.0-or-later */
#include <QVideoSink>
#include <QVideoFrame>
#include <QVariant>
#include <QGuiApplication>
#include <QWindow>
#include <QScreen>
#include <QTimer>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GL/gl.h>
#include <GL/glx.h>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>

namespace {
std::atomic<long long> latestPts{-1};
long long now() {
    return std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
}
void record(const char* event, long long pts, long long a, long long b, const char* output = "") {
    static FILE* file = [] {
        const char* path = std::getenv("BINO_OBSERVER_TRACE");
        FILE* f = path ? std::fopen(path, "w") : nullptr;
        if (f) { std::setvbuf(f, nullptr, _IOLBF, 0); std::fputs("event,start_ns,pts_us,arg1,arg2,output\n", f); }
        return f;
    }();
    if (file) std::fprintf(file, "%s,%lld,%lld,%lld,%lld,%s\n", event, now(), pts, a, b, output);
}
template<class F> F next(const char* name) {
    auto fn = reinterpret_cast<F>(dlsym(RTLD_NEXT, name));
    if (!fn) { std::fprintf(stderr, "Bino observer: unresolved %s\n", name); std::abort(); }
    return fn;
}
void attach(QVideoSink* sink) {
    if (sink->property("_binoObserverAttached").toBool()) return;
    sink->setProperty("_binoObserverAttached", true);
    record("sink_attached", -1, 0, 0);
    auto* timer = new QTimer(sink);
    QObject::connect(timer, &QTimer::timeout, sink, [] {
        for (QWindow* window : QGuiApplication::topLevelWindows()) {
            if (window->isVisible() && window->type() == Qt::Window && window->screen()) {
                const QByteArray output = window->screen()->name().toUtf8();
                record("window", latestPts, window->windowState() == Qt::WindowFullScreen,
                    window->width(), output.constData());
            }
        }
    });
    timer->start(1000);
    QObject::connect(sink, &QVideoSink::videoFrameChanged, sink, [](const QVideoFrame& frame) {
        if (!frame.isValid()) return;
        latestPts = frame.startTime();
        record("source", frame.startTime(), frame.width(), frame.height());
    }, Qt::DirectConnection);
}
}
// Interpose both complete-object and base-object constructors. Bino subclasses QVideoSink.
extern "C" void sinkC1(QVideoSink* self, QObject* parent) asm("_ZN10QVideoSinkC1EP7QObject");
extern "C" void sinkC2(QVideoSink* self, QObject* parent) asm("_ZN10QVideoSinkC2EP7QObject");
extern "C" void sinkC1(QVideoSink* self, QObject* parent) {
    static auto fn = next<void(*)(QVideoSink*, QObject*)>("_ZN10QVideoSinkC1EP7QObject");
    fn(self, parent); attach(self);
}
extern "C" void sinkC2(QVideoSink* self, QObject* parent) {
    static auto fn = next<void(*)(QVideoSink*, QObject*)>("_ZN10QVideoSinkC2EP7QObject");
    fn(self, parent); attach(self);
}
static thread_local decltype(&glTexImage2D) image2d;
static thread_local decltype(&glTexSubImage2D) subimage2d;
static thread_local PFNEGLCREATEIMAGEKHRPROC createImage;
extern "C" void glTexImage2D(GLenum target, GLint level, GLint internalFormat,
        GLsizei w, GLsizei h, GLint border, GLenum format, GLenum type, const void* data) {
    if (!image2d) image2d = next<decltype(&glTexImage2D)>("glTexImage2D");
    if (data) record("texture_upload", latestPts, w, h);
    image2d(target, level, internalFormat, w, h, border, format, type, data);
}
extern "C" void glTexSubImage2D(GLenum target, GLint level, GLint x, GLint y,
        GLsizei w, GLsizei h, GLenum format, GLenum type, const void* data) {
    if (!subimage2d) subimage2d = next<decltype(&glTexSubImage2D)>("glTexSubImage2D");
    if (data) record("texture_upload", latestPts, w, h);
    subimage2d(target, level, x, y, w, h, format, type, data);
}
extern "C" EGLImageKHR eglCreateImageKHR(EGLDisplay d, EGLContext c, EGLenum target,
        EGLClientBuffer buffer, const EGLint* attributes) {
    if (!createImage) createImage = next<PFNEGLCREATEIMAGEKHRPROC>("eglCreateImageKHR");
    EGLImageKHR result = createImage(d, c, target, buffer, attributes);
    if (target == EGL_LINUX_DMA_BUF_EXT)
        record(result == EGL_NO_IMAGE_KHR ? "dmabuf_import_failed" : "dmabuf_import", latestPts, 0, 0);
    return result;
}
static thread_local PFNEGLCREATEIMAGEPROC createCoreImage;
extern "C" EGLImage eglCreateImage(EGLDisplay d, EGLContext c, EGLenum target,
        EGLClientBuffer buffer, const EGLAttrib* attributes) {
    if (!createCoreImage) createCoreImage = next<PFNEGLCREATEIMAGEPROC>("eglCreateImage");
    EGLImage result = createCoreImage(d, c, target, buffer, attributes);
    if (target == EGL_LINUX_DMA_BUF_EXT)
        record(result == EGL_NO_IMAGE ? "dmabuf_import_failed" : "dmabuf_import", latestPts, 0, 0);
    return result;
}
using BindImage = void(*)(GLenum, void*);
static thread_local BindImage bindImage;
extern "C" void glEGLImageTargetTexture2DOES(GLenum target, void* image) {
    if (!bindImage) bindImage = next<BindImage>("glEGLImageTargetTexture2DOES");
    record("egl_image_bind", latestPts, target, 0);
    bindImage(target, image);
}
static void* intercept(const char* name, void* real) {
    if (!real) return real;
    if (!std::strcmp(name, "eglCreateImage")) { createCoreImage = reinterpret_cast<PFNEGLCREATEIMAGEPROC>(real); return reinterpret_cast<void*>(&eglCreateImage); }
    if (!std::strcmp(name, "glEGLImageTargetTexture2DOES")) { bindImage = reinterpret_cast<BindImage>(real); return reinterpret_cast<void*>(&glEGLImageTargetTexture2DOES); }
    if (!std::strcmp(name, "glTexImage2D")) { image2d = reinterpret_cast<decltype(&glTexImage2D)>(real); return reinterpret_cast<void*>(&glTexImage2D); }
    if (!std::strcmp(name, "glTexSubImage2D")) { subimage2d = reinterpret_cast<decltype(&glTexSubImage2D)>(real); return reinterpret_cast<void*>(&glTexSubImage2D); }
    if (!std::strcmp(name, "eglCreateImageKHR")) { createImage = reinterpret_cast<PFNEGLCREATEIMAGEKHRPROC>(real); return reinterpret_cast<void*>(&eglCreateImageKHR); }
    return real;
}
extern "C" __eglMustCastToProperFunctionPointerType eglGetProcAddress(const char* name) {
    static auto fn = next<decltype(&eglGetProcAddress)>("eglGetProcAddress");
    return reinterpret_cast<__eglMustCastToProperFunctionPointerType>(intercept(name, reinterpret_cast<void*>(fn(name))));
}
extern "C" __GLXextFuncPtr glXGetProcAddressARB(const GLubyte* name) {
    static auto fn = next<decltype(&glXGetProcAddressARB)>("glXGetProcAddressARB");
    return reinterpret_cast<__GLXextFuncPtr>(intercept(reinterpret_cast<const char*>(name), reinterpret_cast<void*>(fn(name))));
}
extern "C" __GLXextFuncPtr glXGetProcAddress(const GLubyte* name) {
    static auto fn = next<decltype(&glXGetProcAddress)>("glXGetProcAddress");
    return reinterpret_cast<__GLXextFuncPtr>(intercept(reinterpret_cast<const char*>(name), reinterpret_cast<void*>(fn(name))));
}
