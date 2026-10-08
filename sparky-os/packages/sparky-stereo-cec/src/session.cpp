// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
#include "session.h"
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusServiceWatcher>
#include <QDBusVariant>
#include <QDebug>

namespace
{

const QString service = QStringLiteral("org.freedesktop.login1");
const QString sessionInterface = QStringLiteral("org.freedesktop.login1.Session");
const QString properties = QStringLiteral("org.freedesktop.DBus.Properties");

}

SessionGate::SessionGate(const QDBusConnection &bus, QObject *parent)
    : QObject(parent)
    , m_bus(bus)
{
    auto watcher = new QDBusServiceWatcher(service, bus, QDBusServiceWatcher::WatchForOwnerChange, this);
    connect(watcher, &QDBusServiceWatcher::serviceOwnerChanged, this, [this] {
        resolve();
    });
    resolve();
}

bool SessionGate::isActive() const
{
    return m_active;
}

void SessionGate::setActive(bool active)
{
    if (m_active != active) {
        m_active = active;
        Q_EMIT activeChanged(active);
    }
}

void SessionGate::resolve()
{
    const auto revision = ++m_revision;
    setActive(false);
    if (!m_path.isEmpty()) {
        m_bus.disconnect(service, m_path, properties, QStringLiteral("PropertiesChanged"), this, SLOT(propertiesChanged(QString,QVariantMap,QStringList)));
        m_path.clear();
    }
    auto message = QDBusMessage::createMethodCall(service, QStringLiteral("/org/freedesktop/login1"), QStringLiteral("org.freedesktop.login1.Manager"), QStringLiteral("GetSession"));
    message << qEnvironmentVariable("XDG_SESSION_ID", QStringLiteral("auto"));
    auto watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(message), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, revision, watcher] {
        const QDBusPendingReply<QDBusObjectPath> reply = *watcher;
        watcher->deleteLater();
        if (revision != m_revision) {
            return;
        }
        if (reply.isError()) {
            qWarning() << "CEC session lookup failed:" << reply.error().message();
            return;
        }
        m_path = reply.value().path();
        m_bus.connect(service, m_path, properties, QStringLiteral("PropertiesChanged"), this, SLOT(propertiesChanged(QString,QVariantMap,QStringList)));
        readActive();
    });
}

void SessionGate::readActive()
{
    const auto revision = ++m_revision;
    setActive(false);
    auto message = QDBusMessage::createMethodCall(service, m_path, properties, QStringLiteral("Get"));
    message << sessionInterface << QStringLiteral("Active");
    auto watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(message), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, revision, watcher] {
        const QDBusPendingReply<QDBusVariant> reply = *watcher;
        watcher->deleteLater();
        if (revision == m_revision && !reply.isError()) {
            setActive(reply.value().variant().toBool());
        }
    });
}

void SessionGate::propertiesChanged(const QString &interface, const QVariantMap &changed, const QStringList &invalidated)
{
    if (interface != sessionInterface) {
        return;
    }
    if (changed.contains(QStringLiteral("Active"))) {
        ++m_revision;
        setActive(changed.value(QStringLiteral("Active")).toBool());
    } else if (invalidated.contains(QStringLiteral("Active"))) {
        readActive();
    }
}
