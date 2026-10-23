// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "powerprofiles.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusReply>

using namespace Qt::StringLiterals;

namespace SparkyGraphics
{

static const QString s_service = u"net.hadess.PowerProfiles"_s;
static const QString s_path = u"/net/hadess/PowerProfiles"_s;

bool PowerProfiles::daemonAvailable()
{
    QDBusConnection bus = QDBusConnection::systemBus();
    return bus.isConnected() && bus.interface()->isServiceRegistered(s_service);
}

static QDBusMessage call(const QString &interface, const QString &method, const QVariantList &arguments)
{
    QDBusMessage message = QDBusMessage::createMethodCall(s_service, s_path, interface, method);
    message.setArguments(arguments);
    return QDBusConnection::systemBus().call(message, QDBus::Block, 3000);
}

static QVariant property(const QString &name)
{
    const QDBusMessage reply = call(u"org.freedesktop.DBus.Properties"_s, u"Get"_s, {s_service, name});
    if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty()) {
        return {};
    }
    return reply.arguments().first().value<QDBusVariant>().variant();
}

PowerProfile PowerProfiles::active()
{
    const QString forced = qEnvironmentVariable("SPARKY_STEREO_POWER_PROFILE");
    if (!forced.isEmpty()) {
        return powerProfileFromString(forced);
    }
    if (!daemonAvailable()) {
        return PowerProfile::Balanced;
    }
    return powerProfileFromString(property(u"ActiveProfile"_s).toString());
}

QList<PowerAction> PowerProfiles::gpuActions()
{
    QList<PowerAction> actions;
    if (!daemonAvailable()) {
        return actions;
    }
    const QVariant info = property(u"ActionsInfo"_s);
    if (!info.canConvert<QDBusArgument>()) {
        return actions;
    }
    const QList<QVariantMap> list = qdbus_cast<QList<QVariantMap>>(info.value<QDBusArgument>());
    for (const QVariantMap &entry : list) {
        const QString name = entry.value(u"Name"_s).toString();
        if (!name.contains(u"gpu"_s) && !name.contains(u"panel"_s)) {
            continue;
        }
        actions.append({name, entry.value(u"Description"_s).toString(), entry.value(u"Enabled"_s).toBool()});
    }
    return actions;
}

bool PowerProfiles::setActionEnabled(const QString &name, bool enabled)
{
    if (!daemonAvailable()) {
        return false;
    }
    return call(s_service, u"SetActionEnabled"_s, {name, enabled}).type() == QDBusMessage::ReplyMessage;
}

}
