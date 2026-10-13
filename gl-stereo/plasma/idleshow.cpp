// SPDX-License-Identifier: GPL-2.0-or-later
#include "showsession.h"
#include "stereobackground.h"
#include <QGuiApplication>
#include <QQuickItem>
#include <QScreen>
#include <QWindow>

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    if (app.platformName() != QStringLiteral("wayland") ||
        !qEnvironmentVariable("XDG_CURRENT_DESKTOP").split(u':').contains(QStringLiteral("KDE"))) return 0;
    app.setQuitOnLastWindowClosed(false);
    ShowSession session(false);
    QList<QQuickWindow *> windows;
    auto add = [&](QScreen *screen) {
        auto *window = new QQuickWindow;
        window->setTitle(QStringLiteral("Stereo GL show"));
        window->setScreen(screen);
        window->setFlags(Qt::FramelessWindowHint | Qt::WindowStaysOnTopHint);
        window->setColor(Qt::transparent);
        new StereoBackground(window, session.client());
        QObject::connect(&session, &ShowSession::runningChanged, window, [window](bool running) {
            if (running) window->showFullScreen(); else window->hide();
        });
        windows << window;
        if (session.running()) window->showFullScreen();
    };
    for (QScreen *screen : app.screens()) add(screen);
    QObject::connect(&app, &QGuiApplication::screenAdded, &app, add);
    QObject::connect(&app, &QGuiApplication::screenRemoved, &app, [&](QScreen *screen) {
        for (auto *window : windows) if (window->screen() == screen) { windows.removeOne(window); delete window; break; }
    });
    const int result = app.exec();
    qDeleteAll(windows);
    return result;
}
