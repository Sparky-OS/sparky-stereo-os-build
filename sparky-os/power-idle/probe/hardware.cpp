// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
#include <QCoreApplication>
#include <QDBusConnection>
#include <QTextStream>

class UPower : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.UPower")
    Q_PROPERTY(bool LidIsPresent READ lidIsPresent CONSTANT)

public:
    explicit UPower(bool lid)
        : m_lid(lid)
    {
    }
    bool lidIsPresent() const
    {
        return m_lid;
    }

private:
    bool m_lid;
};

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    UPower upower(app.arguments().contains(QStringLiteral("--laptop")));
    auto bus = QDBusConnection::systemBus();
    if (!bus.registerObject(QStringLiteral("/org/freedesktop/UPower"), &upower, QDBusConnection::ExportAllProperties)
        || !bus.registerService(QStringLiteral("org.freedesktop.UPower"))) {
        return 1;
    }
    QTextStream(stdout) << "READY" << Qt::endl;
    return app.exec();
}

#include "hardware.moc"
