// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Test double for polkitd on a private system bus: answers
// org.freedesktop.PolicyKit1.Authority.CheckAuthorization with "authorized"
// (fakepolkit allow) or "not authorized" (fakepolkit deny), and logs each
// question. KAuth, its D-Bus helper activation and the helper are real.

#include <QCoreApplication>
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusError>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QFile>
#include <QXmlStreamReader>
#include <QDBusVirtualObject>
#include <QTextStream>

using namespace Qt::StringLiterals;

// pkexec discovers the engine-specific action from the real installed policy.
struct PolicyAction {
    QString id, description, message, vendor, url, icon;
    uint any = 0, inactive = 0, active = 0;
    QMap<QString, QString> annotations;
};
Q_DECLARE_METATYPE(PolicyAction)
Q_DECLARE_METATYPE(QList<PolicyAction>)

QDBusArgument &operator<<(QDBusArgument &a, const PolicyAction &p)
{
    a.beginStructure();
    a << p.id << p.description << p.message << p.vendor << p.url << p.icon
      << p.any << p.inactive << p.active << p.annotations;
    a.endStructure();
    return a;
}

const QDBusArgument &operator>>(const QDBusArgument &a, PolicyAction &p)
{
    a.beginStructure();
    a >> p.id >> p.description >> p.message >> p.vendor >> p.url >> p.icon
      >> p.any >> p.inactive >> p.active >> p.annotations;
    a.endStructure();
    return a;
}

static QList<PolicyAction> installedActions()
{
    QFile file(u"/usr/share/polkit-1/actions/org.sparkylinux.sparkystereo.problems.policy"_s);
    if (!file.open(QIODevice::ReadOnly)) {
        return {};
    }
    QXmlStreamReader xml(&file);
    PolicyAction action;
    while (!xml.atEnd()) {
        xml.readNext();
        if (!xml.isStartElement()) {
            continue;
        }
        if (xml.name() == u"action") {
            action.id = xml.attributes().value(u"id"_s).toString();
        } else if (xml.name() == u"annotate") {
            const QString key = xml.attributes().value(u"key"_s).toString();
            action.annotations.insert(key, xml.readElementText());
        }
    }
    return xml.hasError() || action.id.isEmpty() ? QList<PolicyAction>{} : QList<PolicyAction>{action};
}

class Authority : public QDBusVirtualObject
{
public:
    explicit Authority(bool allow)
        : m_allow(allow)
    {
    }

    QString introspect(const QString &) const override
    {
        return u"<interface name=\"org.freedesktop.PolicyKit1.Authority\"/>"_s;
    }

    bool handleMessage(const QDBusMessage &message, const QDBusConnection &connection) override
    {
        QDBusMessage reply = message.createReply();
        if (message.member() == u"CheckAuthorization"_s) {
            QTextStream(stdout) << "CheckAuthorization " << message.arguments().value(1).toString() << ' ' << (m_allow ? "allow" : "deny") << Qt::endl;
            QDBusArgument result;
            result.beginStructure();
            result << m_allow << false;
            result.beginMap(QMetaType::fromType<QString>(), QMetaType::fromType<QString>());
            result.endMap();
            result.endStructure();
            reply << QVariant::fromValue(result);
        } else if (message.member() == u"EnumerateActions"_s) {
            reply << QVariant::fromValue(installedActions());
        } else if (message.member() == u"GetAll"_s) {
            reply << QVariant::fromValue(QVariantMap());
        } else if (message.member() == u"Get"_s) {
            reply << QVariant::fromValue(QDBusVariant(QString()));
        } else {
            reply = message.createErrorReply(QDBusError::UnknownMethod, message.member());
        }
        return connection.send(reply);
    }

private:
    const bool m_allow;
};

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    qDBusRegisterMetaType<PolicyAction>();
    qDBusRegisterMetaType<QList<PolicyAction>>();
    Authority authority(app.arguments().value(1) == u"allow"_s);
    QDBusConnection bus = QDBusConnection::systemBus();
    if (!bus.registerVirtualObject(u"/org/freedesktop/PolicyKit1/Authority"_s, &authority, QDBusConnection::VirtualObjectRegisterOption::SubPath)
        || !bus.registerService(u"org.freedesktop.PolicyKit1"_s)) {
        QTextStream(stderr) << "cannot register: " << bus.lastError().message() << Qt::endl;
        return 1;
    }
    QTextStream(stdout) << "ready" << Qt::endl;
    return app.exec();
}
