// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
// A device's network screen in Stereo KWin: the screencast protocol's version 7 request
// (stream_virtual_output_with_properties). KWin names it Virtual-<name>, marks it networked (KWin +stereo3d66 gives it a
// monitor's 3D formats and eye swap, keeps the person's choice per device and lists it under "Throw to"), and removes it
// when the stream object is closed.
#pragma once

#include <QObject>
#include <QSize>
#include <QSocketNotifier>
#include <memory>

struct wl_display;
struct wl_registry;
struct zkde_screencast_unstable_v1;
struct zkde_screencast_stream_unstable_v1;

namespace Throw
{

// one Wayland connection for the daemon
class WaylandConnection : public QObject
{
    Q_OBJECT
public:
    static WaylandConnection *instance();
    // false when there is no Wayland session or KWin does not give this program the interface: error() says which
    bool ensure();
    QString error() const
    {
        return m_error;
    }
    zkde_screencast_unstable_v1 *screencast() const
    {
        return m_screencast;
    }
    void flush();

    zkde_screencast_unstable_v1 *m_screencast = nullptr;

private:
    WaylandConnection() = default;
    wl_display *m_display = nullptr;
    wl_registry *m_registry = nullptr;
    std::unique_ptr<QSocketNotifier> m_notifier;
    QString m_error;
};

class NetworkScreen : public QObject
{
    Q_OBJECT
public:
    explicit NetworkScreen(QObject *parent = nullptr);
    ~NetworkScreen() override;
    // name: the device's identity; description: its friendly name (the window menu shows it under "Throw to")
    void request(const QString &name, const QString &description, const QSize &size, int refreshMilliHz);
    void close();

    // called from the protocol's listener
    void onCreated(quint32 node);
    void onFailed(const QString &error);
    void onClosed();
    void onSerial(quint64 serial);

Q_SIGNALS:
    void created(quint64 objectSerial, quint32 node);
    void failed(const QString &error);
    void closed();

private:
    zkde_screencast_stream_unstable_v1 *m_stream = nullptr;
    quint64 m_serial = 0;
};

} // namespace Throw
