// SPDX-License-Identifier: GPL-2.0-or-later
#include "stereobackground.h"
#include "frameclient.h"
#include "viewporter-client-protocol.h"
#include <QGuiApplication>
#include <QPlatformSurfaceEvent>
#include <QtGui/qguiapplication_platform.h>
#include <qpa/qplatformwindow_p.h>
#include <wayland-client.h>
#include <stereo-declare.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <vector>

namespace {
struct Globals {
    wl_registry *registry = nullptr;
    wl_compositor *compositor = nullptr;
    wl_subcompositor *subcompositor = nullptr;
    wl_shm *shm = nullptr;
    wp_viewporter *viewporter = nullptr;
    Globals()
    {
        auto *native = qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>();
        if (!native) return;
        stereo_declare_wayland_init(native->display(), nullptr);
        registry = wl_display_get_registry(native->display());
        static const wl_registry_listener listener = {
            [](void *data, wl_registry *registry, uint32_t name, const char *interface, uint32_t version) {
                auto *g = static_cast<Globals *>(data);
                if (!strcmp(interface, "wl_compositor")) g->compositor = static_cast<wl_compositor *>(wl_registry_bind(registry, name, &wl_compositor_interface, qMin(version, 4u)));
                else if (!strcmp(interface, "wl_subcompositor")) g->subcompositor = static_cast<wl_subcompositor *>(wl_registry_bind(registry, name, &wl_subcompositor_interface, 1));
                else if (!strcmp(interface, "wl_shm")) g->shm = static_cast<wl_shm *>(wl_registry_bind(registry, name, &wl_shm_interface, 1));
                else if (!strcmp(interface, "wp_viewporter")) g->viewporter = static_cast<wp_viewporter *>(wl_registry_bind(registry, name, &wp_viewporter_interface, 1));
            },
            [](void *, wl_registry *, uint32_t) {}
        };
        wl_registry_add_listener(registry, &listener, this);
    }
};
Globals &globals()
{
    static Globals g;
    return g;
}
struct Buffer {
    wl_buffer *handle;
    void *mapping;
    size_t size;
    bool busy = false;
    ~Buffer() { wl_buffer_destroy(handle); munmap(mapping, size); }
};
}

struct StereoBackground::Private {
    wl_surface *surface = nullptr;
    wl_subsurface *subsurface = nullptr;
    wp_viewport *viewport = nullptr;
    std::vector<std::unique_ptr<Buffer>> buffers;
    ~Private()
    {
        if (surface) stereo_remove_wayland(surface);
        if (viewport) wp_viewport_destroy(viewport);
        if (subsurface) wl_subsurface_destroy(subsurface);
        if (surface) wl_surface_destroy(surface);
    }
};

StereoBackground::StereoBackground(QQuickWindow *window, FrameClient *client)
    : QObject(window), d(std::make_unique<Private>()), m_window(window), m_client(client), m_color(window->color())
{
    auto format = window->format();
    format.setAlphaBufferSize(8);
    window->setFormat(format);
    globals();
    window->installEventFilter(this);
    connect(client, &FrameClient::frameChanged, this, &StereoBackground::update);
    connect(window, &QWindow::widthChanged, this, &StereoBackground::update);
    connect(window, &QWindow::heightChanged, this, &StereoBackground::update);
}
StereoBackground::~StereoBackground() { reset(); }

void StereoBackground::reset()
{
    d = std::make_unique<Private>();
    if (m_active) {
        m_active = false;
        if (m_window) m_window->setColor(m_color);
        Q_EMIT activeChanged();
    }
}

bool StereoBackground::eventFilter(QObject *, QEvent *event)
{
    if (event->type() == QEvent::PlatformSurface &&
        static_cast<QPlatformSurfaceEvent *>(event)->surfaceEventType() == QPlatformSurfaceEvent::SurfaceAboutToBeDestroyed) reset();
    return false;
}

void StereoBackground::update()
{
    const QImage &frame = m_client->frame();
    if (!m_window || frame.isNull()) { reset(); return; }
    auto &g = globals();
    if (!g.compositor || !g.subcompositor || !g.viewporter || !g.shm || !stereo_supported_wayland()) return;
    auto *native = m_window->nativeInterface<QNativeInterface::Private::QWaylandWindow>();
    if (!native || !native->surface() || m_window->width() < 1 || m_window->height() < 1) return;
    if (!d->surface) {
        d->surface = wl_compositor_create_surface(g.compositor);
        d->subsurface = wl_subcompositor_get_subsurface(g.subcompositor, d->surface, native->surface());
        wl_subsurface_place_below(d->subsurface, native->surface());
        wl_subsurface_set_desync(d->subsurface);
        d->viewport = wp_viewporter_get_viewport(g.viewporter, d->surface);
        wl_region *region = wl_compositor_create_region(g.compositor);
        wl_surface_set_input_region(d->surface, region);
        wl_region_destroy(region);
        if (stereo_declare_wayland_format(d->surface, STEREO_SBS_FULL)) { reset(); return; }
    }
    std::erase_if(d->buffers, [](const auto &buffer) { return !buffer->busy; });
    if (d->buffers.size() >= 2) return;
    const QImage pixels = frame.convertToFormat(QImage::Format_ARGB32);
    const size_t size = pixels.sizeInBytes();
    int fd = memfd_create("gl-stereo-background", MFD_CLOEXEC);
    if (fd < 0) return;
    if (ftruncate(fd, size)) { close(fd); return; }
    void *mapping = mmap(nullptr, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (mapping == MAP_FAILED) { close(fd); return; }
    memcpy(mapping, pixels.constBits(), size);
    wl_shm_pool *pool = wl_shm_create_pool(g.shm, fd, size);
    wl_buffer *handle = wl_shm_pool_create_buffer(pool, 0, pixels.width(), pixels.height(), pixels.bytesPerLine(), WL_SHM_FORMAT_ARGB8888);
    wl_shm_pool_destroy(pool); close(fd);
    auto buffer = std::make_unique<Buffer>(handle, mapping, size, true);
    static const wl_buffer_listener listener = {[](void *data, wl_buffer *) { static_cast<Buffer *>(data)->busy = false; }};
    wl_buffer_add_listener(handle, &listener, buffer.get());
    d->buffers.push_back(std::move(buffer));
    wp_viewport_set_destination(d->viewport, m_window->width(), m_window->height());
    wl_surface_attach(d->surface, handle, 0, 0);
    wl_surface_damage_buffer(d->surface, 0, 0, pixels.width(), pixels.height());
    wl_surface_commit(d->surface);
    if (!m_active) {
        m_active = true;
        m_window->setColor(Qt::transparent);
        Q_EMIT activeChanged();
    }
    m_window->update();
}
