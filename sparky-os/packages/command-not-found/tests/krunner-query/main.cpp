// Created by Daniel Ramos (Capitain Jack) 2026/11/03
// Copyright 2026 under the GNU GPL3 License
// Asks the real KRunner library what a person's KRunner shows for each query: KRunner::RunnerManager with its default
// configuration (krunnerrc), which loads every installed runner the configuration enables, D-Bus runners from
// krunner/dbusplugins included. Prints {query: [[runner, id, text, subtext, relevance], ...]} as JSON.
#include <KRunner/AbstractRunner>
#include <KRunner/QueryMatch>
#include <KRunner/RunnerManager>

#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTextStream>
#include <QTimer>

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    KRunner::RunnerManager manager;
    QJsonObject result;
    for (const QString &query : app.arguments().mid(1)) {
        QEventLoop loop;
        QObject::connect(&manager, &KRunner::RunnerManager::queryFinished, &loop, &QEventLoop::quit);
        QTimer::singleShot(60000, &loop, &QEventLoop::quit);
        manager.launchQuery(query);
        loop.exec();
        QJsonArray matches;
        for (const KRunner::QueryMatch &match : manager.matches()) {
            matches.append(QJsonArray{match.runner() ? match.runner()->id() : QString(), match.id(), match.text(), match.subtext(), match.relevance()});
        }
        result.insert(query, matches);
        manager.matchSessionComplete();
    }
    QTextStream(stdout) << QJsonDocument(result).toJson();
    return 0;
}
