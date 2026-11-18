// Created by Daniel Ramos (Capitain Jack) 2026/11/18
// Copyright 2026 under the GNU GPL3 License
#include <QApplication>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTextStream>
#include <KFilePlacesModel>
#include <KLocalizedString>

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    QJsonObject labels;
    for (const auto &language : {"en", "pl", "pt_BR", "fr", "de", "es", "ja", "ko", "zh_CN", "zh_TW"}) {
        KLocalizedString::setLanguages({QString::fromLatin1(language)});
        KFilePlacesModel places;
        for (int row = 0; row < places.rowCount(); ++row) {
            const auto index = places.index(row, 0);
            if (places.url(index) == QUrl::fromLocalFile(QDir::homePath())) {
                labels.insert(QString::fromLatin1(language), places.text(index));
                break;
            }
        }
    }
    QTextStream(stdout) << QJsonDocument(labels).toJson();
    return labels.size() == 10 ? 0 : 1;
}
