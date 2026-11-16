// SPDX-License-Identifier: GPL-2.0-or-later
#include "editor.h"
#include <QApplication>
#include <QCommandLineParser>
#include <QFile>
#include <QJsonDocument>
#include <QStandardPaths>
#include <QTranslator>
#include <QLocale>
#include <QDBusConnection>
#include <iostream>

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    QTranslator translations;
    const auto path = qEnvironmentVariable("THEME_EDITOR_TRANSLATIONS",
        QStandardPaths::locate(QStandardPaths::GenericDataLocation,
            "sparky-stereo-theme-editor/translations", QStandardPaths::LocateDirectory));
    if (translations.load(QLocale(), "theme-editor", "_", path)) app.installTranslator(&translations);
    QCommandLineParser parser;
    parser.addHelpOption();
    parser.addOption({"theme", QCoreApplication::translate("Cli", "Open an icon theme"), "path"});
    parser.addOption({"icon", QCoreApplication::translate("Cli", "Open an SVG source inside the theme"), "path"});
    parser.addOption({"project", QCoreApplication::translate("Cli", "Open a saved project"), "path"});
    parser.addOption({"places", QCoreApplication::translate("Cli", "Read group depths from JSON"), "path"});
    parser.addOption({"save", QCoreApplication::translate("Cli", "Save a new project copy"), "path"});
    parser.addOption({"flat", QCoreApplication::translate("Cli", "Disable the stereo preview")});
    parser.addOption({"exit-after-save", QCoreApplication::translate("Cli", "Return after the requested save")});
    parser.process(app);
    try {
        Editor editor;
        auto bus = QDBusConnection::sessionBus();
        if (bus.isConnected()) {
            bus.registerObject("/ThemeEditor", &editor, QDBusConnection::ExportAllSlots);
            bus.registerService("org.sparky.ThemeEditor.p" + QString::number(QCoreApplication::applicationPid()));
            bus.registerService("org.sparky.ThemeEditor");
        }
        if (parser.isSet("project")) editor.loadProject(parser.value("project"));
        else if (parser.isSet("theme")) editor.load(parser.value("theme"), parser.value("icon"));
        if (parser.isSet("places")) {
            QFile file(parser.value("places"));
            if (!file.open(QIODevice::ReadOnly)) throw std::runtime_error(QCoreApplication::translate("Cli", "Cannot open the group choices").toStdString());
            QJsonParseError error;
            const auto data = QJsonDocument::fromJson(file.readAll(), &error);
            if (error.error != QJsonParseError::NoError || !data.isObject()) throw std::runtime_error(QCoreApplication::translate("Cli", "Invalid group choices").toStdString());
            editor.applyPlaces(data.object());
        }
        if (parser.isSet("flat")) editor.stereo->setChecked(false);
        if (parser.isSet("save")) editor.saveProject(parser.value("save"));
        if (parser.isSet("exit-after-save")) return 0;
        editor.show();
        return app.exec();
    } catch (const std::exception &e) { std::cerr << e.what() << '\n'; return 1; }
}
