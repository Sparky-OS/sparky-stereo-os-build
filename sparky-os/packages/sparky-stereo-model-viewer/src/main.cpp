// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
#include "viewer.h"

#include <KAboutData>
#include <KLocalizedQmlContext>
#include <KLocalizedString>

#include <QApplication>
#include <QCommandLineParser>
#include <QFileInfo>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QSurfaceFormat>

int main(int argc, char *argv[])
{
    // The 3D area is a child window of the program's own window, made by libf3d on the X display (Xwayland under Plasma): the
    // program's window has to be an X window too, unless the person chose another platform
    if (qEnvironmentVariableIsEmpty("QT_QPA_PLATFORM")) {
        qputenv("QT_QPA_PLATFORM", "xcb");
    }
    QApplication app(argc, argv);
    KLocalizedString::setApplicationDomain("stereo-model-viewer");
    QCoreApplication::setApplicationName(QStringLiteral("stereo-model-viewer"));
    QGuiApplication::setDesktopFileName(QStringLiteral("org.sparkystereo.ModelViewer"));
    QGuiApplication::setWindowIcon(QIcon::fromTheme(QStringLiteral("applications-graphics")));
    if (qEnvironmentVariableIsEmpty("QT_QUICK_CONTROLS_STYLE")) {
        QQuickStyle::setStyle(QStringLiteral("org.kde.desktop"));
    }

    KAboutData about(QStringLiteral("stereo-model-viewer"), i18nc("@title", "Stereo Model Viewer"), QStringLiteral("0.1.2"),
                     i18nc("@title", "Open a 3D model, look at it and turn it"), KAboutLicense::GPL_V3,
                     QStringLiteral("© 2026 Daniel Ramos (Capitain Jack)"));
    about.setDesktopFileName(QStringLiteral("org.sparkystereo.ModelViewer"));
    KAboutData::setApplicationData(about);

    QCommandLineParser parser;
    about.setupCommandLine(&parser);
    parser.addPositionalArgument(QStringLiteral("file"), i18nc("@info:shell", "A model to open"), QStringLiteral("[file]"));
    parser.process(app);
    about.processCommandLine(&parser);

    Viewer viewer;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextObject(new KLocalizedQmlContext(&engine));
    engine.rootContext()->setContextProperty(QStringLiteral("viewer"), &viewer);
    engine.load(QUrl(QStringLiteral("qrc:/ui/Main.qml")));
    if (engine.rootObjects().isEmpty()) {
        return 1;
    }
    const QStringList files = parser.positionalArguments();
    if (!files.isEmpty()) {
        viewer.openPath(QFileInfo(files.first()).absoluteFilePath());
    }
    return app.exec();
}
