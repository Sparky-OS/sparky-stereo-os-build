// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
// sparky-stereo-throwd: the Throw daemon of the person's session (a systemd user service).
#include "daemon.h"
#include "logging.h"

#include <KLocalizedString>
#include <QGuiApplication>

int main(int argc, char **argv)
{
    // no window of its own: notifications go over D-Bus, the network screen over its own Wayland connection
    qputenv("QT_QPA_PLATFORM", "offscreen");
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("sparky-stereo-throwd"));
    app.setQuitOnLastWindowClosed(false);
    KLocalizedString::setApplicationDomain("sparky-stereo-throw");
    Throw::Daemon daemon;
    if (!daemon.start()) {
        return 1;
    }
    return app.exec();
}
