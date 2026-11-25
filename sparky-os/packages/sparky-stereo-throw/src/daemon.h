// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
// The one engine that knows Cast (org.sparky.Throw on the session bus): the devices found, a Throw to each, and what a
// device lets the PC read and set without the person's Google account. The command and the System Settings page talk
// to it; nothing else speaks Cast.
#pragma once

#include "devicetable.h"
#include "discovery.h"
#include "throwsession.h"

#include <QDBusContext>
#include <QDBusMessage>
#include <QHash>
#include <QNetworkAccessManager>
#include <QObject>
#include <QPointer>

namespace Throw
{

class Daemon : public QObject, protected QDBusContext
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.sparky.Throw")
public:
    explicit Daemon(QObject *parent = nullptr);
    bool start();

public Q_SLOTS:
    // JSON: every device found, with its model row, its mode and its Throw's state
    QString Devices();
    // "" when the Throw is starting, else why it cannot
    QString Throw(const QString &id);
    QString Stop(const QString &id);
    // JSON, answered when the device has: its own information (eureka_info, no account) and its receiver status
    QString DeviceInfo(const QString &id);
    // the receiver's volume and mute, as the device's platform receiver takes them without an account; read back after
    QString SetVolume(const QString &id, double level, int muted);

Q_SIGNALS:
    void DevicesChanged();
    void StateChanged(const QString &id, const QString &state, const QString &detail);

private:
    QJsonObject describe(const Device &device) const;
    void finishInfo(const QString &id);

    Discovery m_discovery;
    DeviceTable m_table;
    QHash<QString, QPointer<ThrowSession>> m_sessions;
    // the last state of each device's Throw, kept after its session ends so the reason of a failure stays readable
    QHash<QString, QPair<QString, QString>> m_lastState;
    QNetworkAccessManager m_network;
    struct InfoRequest {
        QList<QDBusMessage> replies;
        QJsonObject info;
        int pending = 0;
    };
    QHash<QString, InfoRequest> m_info;
};

} // namespace Throw
