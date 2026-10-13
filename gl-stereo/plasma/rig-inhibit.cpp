// SPDX-License-Identifier: GPL-2.0-or-later
#include "idle-inhibit-client-protocol.h"
#include <QGuiApplication>
#include <QQuickWindow>
#include <QTimer>
#include <QtGui/qguiapplication_platform.h>
#include <qpa/qplatformwindow_p.h>
#include <wayland-client.h>
#include <cstring>
int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    if (!qEnvironmentVariableIsSet("GL_STEREO_PRIVATE_RIG")) return 2;
    auto *native = app.nativeInterface<QNativeInterface::QWaylandApplication>();
    if (!native) return 3;
    zwp_idle_inhibit_manager_v1 *manager = nullptr;
    auto *registry = wl_display_get_registry(native->display());
    static const wl_registry_listener listener = {
        [](void *data, wl_registry *registry, uint32_t name, const char *interface, uint32_t) {
            if (!strcmp(interface, "zwp_idle_inhibit_manager_v1"))
                *static_cast<zwp_idle_inhibit_manager_v1 **>(data) = static_cast<zwp_idle_inhibit_manager_v1 *>(wl_registry_bind(registry, name, &zwp_idle_inhibit_manager_v1_interface, 1));
        }, [](void *, wl_registry *, uint32_t) {}};
    wl_registry_add_listener(registry, &listener, &manager);
    wl_display_roundtrip(native->display());
    if (!manager) return 4;
    QQuickWindow window;
    window.setColor(Qt::darkGray);
    window.showFullScreen();
    zwp_idle_inhibitor_v1 *inhibitor = nullptr;
    QTimer::singleShot(200, &app, [&] {
        auto *surface = window.nativeInterface<QNativeInterface::Private::QWaylandWindow>();
        if (!surface || !surface->surface()) { app.exit(5); return; }
        inhibitor = zwp_idle_inhibit_manager_v1_create_inhibitor(manager, surface->surface());
        wl_display_flush(native->display());
    });
    const int result = app.exec();
    if (inhibitor) zwp_idle_inhibitor_v1_destroy(inhibitor);
    zwp_idle_inhibit_manager_v1_destroy(manager);
    wl_registry_destroy(registry);
    return result;
}
