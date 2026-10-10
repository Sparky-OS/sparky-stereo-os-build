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
#include <QDBusVirtualObject>
#include <QTextStream>

using namespace Qt::StringLiterals;

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
