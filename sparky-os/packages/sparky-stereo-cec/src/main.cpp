// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
#include "controller.h"
#include "session.h"
#include <KConfigGroup>
#include <KSharedConfig>
#include <QDebug>
#include <QGuiApplication>

int main(int argc, char **argv)
{
    if (!qEnvironmentVariable("XDG_CURRENT_DESKTOP").split(QLatin1Char(':')).contains(QStringLiteral("KDE"))
        || qEnvironmentVariable("XDG_SESSION_TYPE") != QStringLiteral("wayland")) {
        return 0;
    }
    QGuiApplication app(argc, argv);
    app.setQuitOnLastWindowClosed(false);
    if (!QGuiApplication::platformName().startsWith(QStringLiteral("wayland"))) {
        return 0;
    }
    const auto config = KSharedConfig::openConfig(QStringLiteral("sparky-stereo-cecrc"));
    const KConfigGroup group(config, QStringLiteral("Adapters"));
    QHash<QString, QString> bindings;
    for (const auto &key : group.keyList()) {
        bindings.insert(key, group.readEntry(key, QString()));
    }
    CecController controller(QStringLiteral("/dev"), QStringLiteral("/sys/class/drm"), bindings);
    SessionGate session(QDBusConnection::systemBus());
    QObject::connect(&session, &SessionGate::activeChanged, &controller, &CecController::setSessionActive);
    controller.setSessionActive(session.isActive());
    QObject::connect(&controller, &CecController::failed, &app, [](const QString &message) {
        qWarning().noquote() << message;
    });
    QObject::connect(&controller, &CecController::skipped, &app, [](const QString &message) {
        qInfo().noquote() << message;
    });
    return app.exec();
}
