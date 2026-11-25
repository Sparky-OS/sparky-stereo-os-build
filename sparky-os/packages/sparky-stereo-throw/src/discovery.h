// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
// Cast devices on the network, as they announce themselves: DNS-SD `_googlecast._tcp` through KDNSSD (Avahi).
#pragma once

#include <QHash>
#include <QHostAddress>
#include <QObject>
#include <QString>

#include <KDNSSD/RemoteService>
#include <KDNSSD/ServiceBrowser>

namespace Throw
{

struct Device {
    QString id; // TXT `id`, the device's identity (the network screen's name)
    QString name; // TXT `fn`, the friendly name the person gave it
    QString model; // TXT `md`
    QString host;
    QHostAddress address;
    quint16 port = 8009;
    bool group = false; // a service on a port other than 8009 is a cast group (pychromecast discovery.py)
    QString service; // the DNS-SD service name, to match its removal
};

class Discovery : public QObject
{
    Q_OBJECT
public:
    explicit Discovery(QObject *parent = nullptr);
    // false when DNS-SD is not available (Avahi not running): error() says so
    bool start();
    QString error() const
    {
        return m_error;
    }
    QList<Device> devices() const
    {
        return m_devices.values();
    }
    std::optional<Device> device(const QString &id) const;

Q_SIGNALS:
    void deviceAdded(const Throw::Device &device);
    void deviceRemoved(const QString &id);

private:
    void onAdded(KDNSSD::RemoteService::Ptr service);
    void onRemoved(KDNSSD::RemoteService::Ptr service);

    KDNSSD::ServiceBrowser *m_browser = nullptr;
    QHash<QString, Device> m_devices;
    QString m_error;
};

} // namespace Throw
