// SPDX-License-Identifier: GPL-2.0-or-later
#include "editor.h"
#include <QApplication>
#include <QDir>
#include <QFile>
#include <QLocale>
#include <QTranslator>
#include <QJsonArray>
#include <QJsonDocument>
#include <iostream>

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    if (argc != 4) return 2;
    QJsonArray results;
    try {
        for (const auto &language : QStringList{"en", "pl", "pt_BR", "fr", "de", "es", "ja", "ko", "zh_CN", "zh_TW"}) {
            const QString locale = language == "es" ? "es_MX" : language == "fr" ? "fr_CA" : language;
            QLocale::setDefault(QLocale(locale));
            QTranslator catalogue;
            if (!catalogue.load(QLocale(locale), "theme-editor", "_", QString::fromLocal8Bit(argv[3])))
                throw std::runtime_error("Cannot load compiled catalogue: " + language.toStdString());
            app.installTranslator(&catalogue);
            QFile source(QString::fromLocal8Bit(argv[2]) + "/theme-editor_" + language + ".ts");
            if (!source.open(QIODevice::ReadOnly)) throw std::runtime_error("Missing authored catalogue");
            QDomDocument expected;
            if (!expected.setContent(source.readAll())) throw std::runtime_error("Invalid authored catalogue");
            int count = 0;
            for (auto context = expected.documentElement().firstChildElement("context"); !context.isNull(); context = context.nextSiblingElement("context")) {
                const auto name = context.firstChildElement("name").text().toUtf8();
                for (auto message = context.firstChildElement("message"); !message.isNull(); message = message.nextSiblingElement("message")) {
                    const auto text = message.firstChildElement("source").text().toUtf8();
                    const auto translation = message.firstChildElement("translation").text();
                    if (translation.isEmpty() || catalogue.translate(name.constData(), text.constData()) != translation)
                        throw std::runtime_error("Compiled catalogue differs: " + language.toStdString() + ": " + text.toStdString());
                    ++count;
                }
            }
            Editor editor;
            editor.loadProject(QString::fromLocal8Bit(argv[1]));
            auto state = QJsonDocument::fromJson(editor.sessionState().toUtf8()).object();
            const auto title = catalogue.translate("Editor", "Theme editor") + "[*]";
            if (editor.windowTitle() != title || editor.stereo->text() != catalogue.translate("Editor", "Enable 3D"))
                throw std::runtime_error("Runtime widget did not use compiled catalogue");
            results.append(QJsonObject{{"language", language}, {"locale", locale}, {"compiledMessages", count},
                {"title", state.value("title")}, {"enable3d", state.value("enable3d")}, {"partHeader", state.value("partHeader")}});
            app.removeTranslator(&catalogue);
        }
        std::cout << QJsonDocument(results).toJson().constData();
        return 0;
    } catch (const std::exception &e) { std::cerr << e.what() << '\n'; return 1; }
}
