// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
#include "networkscreen.h"
#include "logging.h"

#include "zkde-screencast-unstable-v1-client-protocol.h"

#include <cstring>
#include <wayland-client.h>

namespace Throw
{

namespace
{
void global(void *data, wl_registry *registry, uint32_t name, const char *interface, uint32_t version)
{
    auto connection = static_cast<WaylandConnection *>(data);
    if (!std::strcmp(interface, zkde_screencast_unstable_v1_interface.name) && version >= 7) {
        connection->m_screencast = static_cast<zkde_screencast_unstable_v1 *>(wl_registry_bind(registry, name, &zkde_screencast_unstable_v1_interface, 7));
    }
}
void globalRemove(void *, wl_registry *, uint32_t)
{
}
const wl_registry_listener registryListener{global, globalRemove};

void streamClosed(void *data, zkde_screencast_stream_unstable_v1 *)
{
    static_cast<NetworkScreen *>(data)->onClosed();
}
void streamCreated(void *data, zkde_screencast_stream_unstable_v1 *, uint32_t node)
{
    static_cast<NetworkScreen *>(data)->onCreated(node);
}
void streamFailed(void *data, zkde_screencast_stream_unstable_v1 *, const char *error)
{
    static_cast<NetworkScreen *>(data)->onFailed(QString::fromUtf8(error));
}
void streamSerial(void *data, zkde_screencast_stream_unstable_v1 *, uint32_t high, uint32_t low)
{
    static_cast<NetworkScreen *>(data)->onSerial(quint64(high) << 32 | low);
}
const zkde_screencast_stream_unstable_v1_listener streamListener{streamClosed, streamCreated, streamFailed, streamSerial};
} // namespace

WaylandConnection *WaylandConnection::instance()
{
    static WaylandConnection connection;
    return &connection;
}

bool WaylandConnection::ensure()
{
    if (m_screencast) {
        return true;
    }
    if (!m_display) {
        m_display = wl_display_connect(nullptr);
        if (!m_display) {
            m_error = QStringLiteral("no Wayland session (WAYLAND_DISPLAY)");
            return false;
        }
        m_notifier = std::make_unique<QSocketNotifier>(wl_display_get_fd(m_display), QSocketNotifier::Read);
        connect(m_notifier.get(), &QSocketNotifier::activated, this, [this] {
            if (wl_display_dispatch(m_display) < 0) {
                qCWarning(THROW) << "the Wayland connection ended";
                m_notifier->setEnabled(false);
            }
        });
        m_registry = wl_display_get_registry(m_display);
        wl_registry_add_listener(m_registry, &registryListener, this);
    }
    wl_display_roundtrip(m_display);
    if (!m_screencast) {
        // KWin gives zkde_screencast_unstable_v1 only to a program whose desktop file lists it (X-KDE-Wayland-Interfaces)
        m_error = QStringLiteral("KWin does not offer zkde_screencast_unstable_v1 version 7 to this program");
        return false;
    }
    return true;
}

void WaylandConnection::flush()
{
    if (m_display) {
        wl_display_flush(m_display);
    }
}

NetworkScreen::NetworkScreen(QObject *parent)
    : QObject(parent)
{
}

NetworkScreen::~NetworkScreen()
{
    close();
}

void NetworkScreen::request(const QString &name, const QString &description, const QSize &size, int refreshMilliHz)
{
    auto connection = WaylandConnection::instance();
    if (!connection->ensure()) {
        Q_EMIT failed(connection->error());
        return;
    }
    // scale 1, no millimetres, not a headset (no split eyes), the pointer drawn into the stream
    m_stream = zkde_screencast_unstable_v1_stream_virtual_output_with_properties(connection->screencast(), name.toUtf8().constData(),
        description.toUtf8().constData(), size.width(), size.height(), uint32_t(refreshMilliHz), wl_fixed_from_int(1), 0, 0, 0,
        ZKDE_SCREENCAST_UNSTABLE_V1_POINTER_EMBEDDED);
    zkde_screencast_stream_unstable_v1_add_listener(m_stream, &streamListener, this);
    connection->flush();
    qCInfo(THROW) << "asked KWin for the network screen" << name << size << refreshMilliHz << "mHz";
}

void NetworkScreen::close()
{
    if (m_stream) {
        zkde_screencast_stream_unstable_v1_close(m_stream);
        m_stream = nullptr;
        WaylandConnection::instance()->flush();
    }
}

void NetworkScreen::onCreated(quint32 node)
{
    qCInfo(THROW) << "network screen created, node" << node << "serial" << m_serial;
    Q_EMIT created(m_serial, node);
}

void NetworkScreen::onFailed(const QString &error)
{
    qCWarning(THROW) << "KWin refused the network screen:" << error;
    if (m_stream) {
        zkde_screencast_stream_unstable_v1_destroy(m_stream);
        m_stream = nullptr;
    }
    Q_EMIT failed(error);
}

void NetworkScreen::onClosed()
{
    qCInfo(THROW) << "KWin closed the network screen's stream";
    if (m_stream) {
        zkde_screencast_stream_unstable_v1_destroy(m_stream);
        m_stream = nullptr;
    }
    Q_EMIT closed();
}

void NetworkScreen::onSerial(quint64 serial)
{
    m_serial = serial;
}

} // namespace Throw
