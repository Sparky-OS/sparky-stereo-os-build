// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
#include "pairsurface.h"
#include "viewporter-client-protocol.h"

#include <QGuiApplication>
#include <QLoggingCategory>
#include <QPlatformSurfaceEvent>
#include <QtGui/qguiapplication_platform.h>
#include <qpa/qplatformwindow_p.h>

#include <fcntl.h>
#include <stereo-declare.h>
#include <sys/mman.h>
#include <unistd.h>
#include <vector>
#include <wayland-client.h>

Q_LOGGING_CATEGORY(pairLog, "org.sparky.stereo.screensavers", QtWarningMsg)

namespace
{
struct Globals {
    wl_display *display = nullptr;
    wl_registry *registry = nullptr;
    wl_compositor *compositor = nullptr;
    wl_subcompositor *subcompositor = nullptr;
    wl_shm *shm = nullptr;
    wp_viewporter *viewporter = nullptr;
    Globals()
    {
        auto *native = qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>();
        if (!native) {
            return;
        }
        display = native->display();
        stereo_declare_wayland_init(display, nullptr);
        registry = wl_display_get_registry(display);
        static const wl_registry_listener listener = {
            [](void *data, wl_registry *registry, uint32_t name, const char *interface, uint32_t version) {
                auto *g = static_cast<Globals *>(data);
                if (!strcmp(interface, "wl_compositor")) {
                    g->compositor = static_cast<wl_compositor *>(wl_registry_bind(registry, name, &wl_compositor_interface, qMin(version, 4u)));
                } else if (!strcmp(interface, "wl_subcompositor")) {
                    g->subcompositor = static_cast<wl_subcompositor *>(wl_registry_bind(registry, name, &wl_subcompositor_interface, 1));
                } else if (!strcmp(interface, "wl_shm")) {
                    g->shm = static_cast<wl_shm *>(wl_registry_bind(registry, name, &wl_shm_interface, 1));
                } else if (!strcmp(interface, "wp_viewporter")) {
                    g->viewporter = static_cast<wp_viewporter *>(wl_registry_bind(registry, name, &wp_viewporter_interface, 1));
                }
            },
            [](void *, wl_registry *, uint32_t) {}};
        wl_registry_add_listener(registry, &listener, this);
        wl_display_roundtrip(display);
        wl_display_roundtrip(display);
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
    ~Buffer()
    {
        wl_buffer_destroy(handle);
        munmap(mapping, size);
    }
};
}

struct PairSurface::Private {
    wl_surface *surface = nullptr;
    wl_subsurface *subsurface = nullptr;
    wp_viewport *viewport = nullptr;
    wl_surface *parent = nullptr;
    std::vector<std::unique_ptr<Buffer>> buffers;
    stereo_depth_limits screen{};
    bool haveLimits = false;
    QRect placed;
    ~Private()
    {
        buffers.clear();
        if (surface) {
            stereo_depth_wayland_unwatch(surface);
            stereo_remove_wayland(surface);
        }
        if (viewport) {
            wp_viewport_destroy(viewport);
        }
        if (subsurface) {
            wl_subsurface_destroy(subsurface);
        }
        if (surface) {
            wl_surface_destroy(surface);
        }
    }
};

PairSurface::PairSurface(QObject *parent)
    : QObject(parent)
    , d(std::make_unique<Private>())
{
}

PairSurface::~PairSurface()
{
    hide();
}

bool PairSurface::supported()
{
    auto &g = globals();
    return g.compositor && g.subcompositor && g.shm && g.viewporter && stereo_supported_wayland();
}

void PairSurface::hide()
{
    const bool had = d->surface;
    wl_surface *parent = d->parent;
    d = std::make_unique<Private>();
    m_active = false;
    if (had && parent && m_host) {
        m_host->requestUpdate(); // the sub-surface leaves with its parent's next commit
    }
}

bool PairSurface::eventFilter(QObject *, QEvent *event)
{
    if (event->type() == QEvent::PlatformSurface
        && static_cast<QPlatformSurfaceEvent *>(event)->surfaceEventType() == QPlatformSurfaceEvent::SurfaceAboutToBeDestroyed) {
        hide();
    }
    return false;
}

bool PairSurface::place(QWindow *host, const QRect &rect)
{
    m_failure.clear();
    if (!supported()) {
        m_failure = QStringLiteral("no-stereo-compositor");
        return false;
    }
    if (host != m_host) {
        hide();
        if (m_host) {
            m_host->removeEventFilter(this);
        }
        m_host = host;
        if (m_host) {
            m_host->installEventFilter(this);
        }
    }
    m_rect = rect;
    if (!m_host || rect.width() < 2 || rect.height() < 2) {
        hide();
        m_failure = QStringLiteral("no-place");
        return false;
    }
    auto *native = m_host->nativeInterface<QNativeInterface::Private::QWaylandWindow>();
    wl_surface *parent = native ? native->surface() : nullptr;
    if (!parent) {
        hide();
        m_failure = QStringLiteral("no-window-surface");
        return false;
    }
    auto &g = globals();
    if (d->surface && d->parent != parent) {
        hide();
    }
    if (!d->surface) {
        d->parent = parent;
        d->surface = wl_compositor_create_surface(g.compositor);
        d->subsurface = wl_subcompositor_get_subsurface(g.subcompositor, d->surface, parent);
        wl_subsurface_place_above(d->subsurface, parent);
        wl_subsurface_set_desync(d->subsurface);
        d->viewport = wp_viewporter_get_viewport(g.viewporter, d->surface);
        wl_region *region = wl_compositor_create_region(g.compositor);
        wl_surface_set_input_region(d->surface, region); // keys and the pointer stay the window's
        wl_region_destroy(region);
        if (const int error = stereo_declare_wayland_format(d->surface, STEREO_SBS_FULL)) {
            qCWarning(pairLog) << "the compositor did not take the pair's declaration:" << error;
            hide();
            m_failure = QStringLiteral("declaration-refused");
            return false;
        }
        static const auto onLimits = [](void *data, wl_surface *, const stereo_depth_limits *limits) {
            auto *self = static_cast<PairSurface *>(data);
            self->d->screen = *limits;
            self->d->haveLimits = true;
            Q_EMIT self->limitsChanged();
        };
        if (stereo_depth_wayland_watch_limits(d->surface, onLimits, this) == 0) {
            stereo_depth_limits read{};
            if (stereo_depth_wayland_get_limits(d->surface, &read) == 0) {
                d->screen = read;
                d->haveLimits = true;
            }
        }
    }
    if (d->placed != rect) {
        d->placed = rect;
        wl_subsurface_set_position(d->subsurface, rect.x(), rect.y());
        m_host->requestUpdate(); // a sub-surface's place applies with its parent's next commit
    }
    return true;
}

bool PairSurface::limits(double output, double buffer, double shown, double *sunk, double *popped) const
{
    if (!d->haveLimits || output <= 0 || buffer <= 0 || shown <= 0) {
        return false;
    }
    stereo_depth_limits out{};
    if (stereo_depth_limits_for_buffer(&d->screen, output, buffer, shown, &out) != 0) {
        return false;
    }
    *sunk = out.sunk;
    *popped = out.popped;
    return true;
}

bool PairSurface::show(const QImage &pair)
{
    if (!d->surface || pair.isNull() || pair.width() % 2) {
        return false;
    }
    auto &g = globals();
    std::erase_if(d->buffers, [](const auto &buffer) {
        return !buffer->busy;
    });
    if (d->buffers.size() >= 3) {
        return true; // the compositor still holds the earlier pictures: this one is skipped
    }
    const QImage pixels = pair.convertToFormat(QImage::Format_ARGB32);
    const size_t size = pixels.sizeInBytes();
    const int fd = memfd_create("sparky-saver-pair", MFD_CLOEXEC);
    if (fd < 0) {
        return false;
    }
    void *mapping = ftruncate(fd, size) ? MAP_FAILED : mmap(nullptr, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (mapping == MAP_FAILED) {
        close(fd);
        return false;
    }
    memcpy(mapping, pixels.constBits(), size);
    wl_shm_pool *pool = wl_shm_create_pool(g.shm, fd, size);
    wl_buffer *handle = wl_shm_pool_create_buffer(pool, 0, pixels.width(), pixels.height(), pixels.bytesPerLine(), WL_SHM_FORMAT_XRGB8888);
    wl_shm_pool_destroy(pool);
    close(fd);
    auto buffer = std::make_unique<Buffer>(handle, mapping, size, true);
    static const wl_buffer_listener listener = {[](void *data, wl_buffer *) {
        static_cast<Buffer *>(data)->busy = false;
    }};
    wl_buffer_add_listener(handle, &listener, buffer.get());
    d->buffers.push_back(std::move(buffer));
    wp_viewport_set_destination(d->viewport, m_rect.width(), m_rect.height());
    wl_surface_attach(d->surface, handle, 0, 0);
    wl_surface_damage_buffer(d->surface, 0, 0, pixels.width(), pixels.height());
    wl_surface_commit(d->surface);
    if (!m_active) {
        m_active = true;
        if (m_host) {
            m_host->requestUpdate();
        }
    }
    return true;
}
