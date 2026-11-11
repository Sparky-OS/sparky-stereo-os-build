// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "notifier.h"

#include <KLocalizedString>

#include <QGuiApplication>

int main(int argc, char **argv)
{
    // the notifier shows no window of its own: it needs no display, and the programs it starts (kdialog) keep the
    // session's own platform
    const bool had = qEnvironmentVariableIsSet("QT_QPA_PLATFORM");
    const QByteArray platform = qgetenv("QT_QPA_PLATFORM");
    qputenv("QT_QPA_PLATFORM", "offscreen");
    QGuiApplication app(argc, argv);
    if (had) {
        qputenv("QT_QPA_PLATFORM", platform);
    } else {
        qunsetenv("QT_QPA_PLATFORM");
    }
    app.setQuitOnLastWindowClosed(false);
    app.setApplicationName(QStringLiteral("sparky-stereo-problems-notifier"));
    KLocalizedString::setApplicationDomain("sparky-stereo-problems-plasma");
    Notifier notifier;
    notifier.start();
    return app.exec();
}
