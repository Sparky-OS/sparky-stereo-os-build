// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "launchwatch.h"
#include "graphicssettings.h"

#include <KConfig>
#include <KConfigGroup>

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusReply>
#include <QDBusVariant>
#include <QProcess>
#include <QRegularExpression>

using namespace Qt::StringLiterals;

namespace SparkyGraphics
{

double UnitFacts::seconds() const
{
    if (activeEnter <= 0 || inactiveEnter < activeEnter) {
        return -1;
    }
    return double(inactiveEnter - activeEnter) / 1e6;
}

namespace LaunchWatch
{


int window()
{
    KConfig config(GraphicsSettings::configName(), KConfig::SimpleConfig);
    bool ok = false;
    const int value = config.group(u"Launch"_s).readEntry("DiedWithin", QString::number(defaultWindow)).trimmed().toInt(&ok);
    return ok && value >= 0 && value <= 600 ? value : defaultWindow;
}

// systemd escapes a name with \xNN for every byte outside [A-Za-z0-9:_.]; KIO does the same (escapeUnitName)
static QString unescapeUnit(const QString &escaped)
{
    QByteArray out;
    const QByteArray in = escaped.toUtf8();
    for (int i = 0; i < in.size(); ++i) {
        if (in.at(i) == '\\' && i + 3 < in.size() && in.at(i + 1) == 'x') {
            bool ok = false;
            const int byte = in.mid(i + 2, 2).toInt(&ok, 16);
            if (ok) {
                out.append(char(byte));
                i += 3;
                continue;
            }
        }
        out.append(in.at(i));
    }
    return QString::fromUtf8(out);
}

QString appNameOf(const QString &unit)
{
    static const QRegularExpression pattern(QStringLiteral(R"(^app-(.+)@[0-9a-fA-F]+\.service$)"));
    const auto match = pattern.match(unit);
    return match.hasMatch() ? unescapeUnit(match.captured(1)) : QString();
}

QString keyOf(const QString &appName)
{
    return u"died-"_s + appName;
}

static const QString s_service = u"org.freedesktop.systemd1"_s;

UnitFacts read(const QString &unit)
{
    UnitFacts facts;
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        facts.error = u"no-bus"_s;
        return facts;
    }
    QDBusMessage get = QDBusMessage::createMethodCall(s_service, u"/org/freedesktop/systemd1"_s, u"org.freedesktop.systemd1.Manager"_s, u"GetUnit"_s);
    get << unit;
    const QDBusMessage path = bus.call(get, QDBus::Block, 3000);
    if (path.type() != QDBusMessage::ReplyMessage || path.arguments().isEmpty()) {
        facts.error = path.errorMessage();
        return facts;
    }
    const QString object = path.arguments().first().value<QDBusObjectPath>().path();
    const auto all = [&](const QString &interface) {
        QDBusMessage message = QDBusMessage::createMethodCall(s_service, object, u"org.freedesktop.DBus.Properties"_s, u"GetAll"_s);
        message << interface;
        const QDBusMessage reply = bus.call(message, QDBus::Block, 3000);
        QVariantMap map;
        if (reply.type() == QDBusMessage::ReplyMessage && !reply.arguments().isEmpty()) {
            const QDBusArgument argument = reply.arguments().first().value<QDBusArgument>();
            argument >> map;
        }
        return map;
    };
    const QVariantMap unitProperties = all(u"org.freedesktop.systemd1.Unit"_s);
    const QVariantMap serviceProperties = all(u"org.freedesktop.systemd1.Service"_s);
    if (unitProperties.isEmpty() || serviceProperties.isEmpty()) {
        facts.error = u"no-properties"_s;
        return facts;
    }
    facts.found = true;
    facts.sourcePath = unitProperties.value(u"SourcePath"_s).toString();
    facts.activeEnter = qint64(unitProperties.value(u"ActiveEnterTimestampMonotonic"_s).toULongLong());
    facts.inactiveEnter = qint64(unitProperties.value(u"InactiveEnterTimestampMonotonic"_s).toULongLong());
    facts.result = serviceProperties.value(u"Result"_s).toString();
    facts.exitCode = serviceProperties.value(u"ExecMainStatus"_s).toInt();
    facts.environment = serviceProperties.value(u"Environment"_s).toStringList();
    return facts;
}

QString lastLines(const QString &unit)
{
    QProcess journal;
    journal.start(u"journalctl"_s, {u"--user"_s, u"--unit"_s, unit, u"--lines=8"_s, u"--output=cat"_s, u"--no-pager"_s});
    if (!journal.waitForFinished(3000) || journal.exitStatus() != QProcess::NormalExit || journal.exitCode() != 0) {
        journal.kill();
        return {};
    }
    QString text = QString::fromUtf8(journal.readAllStandardOutput()).trimmed();
    if (text.size() > 1500) {
        text = text.right(1500);
    }
    return text;
}

}

}
