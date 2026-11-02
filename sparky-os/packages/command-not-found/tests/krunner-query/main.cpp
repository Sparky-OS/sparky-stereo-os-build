// Created by Daniel Ramos (Capitain Jack) 2026/11/02
// Copyright 2026 under the GNU GPL3 License
// Asks the real KRunner library what a person's KRunner shows for each query: KRunner::RunnerManager with its default
// configuration (krunnerrc), which loads every installed runner the configuration enables, D-Bus runners from
// krunner/dbusplugins included. Prints {query: [[runner, id, text, subtext, relevance], ...]} as JSON.
// With --run first, it also runs each query's first match whose id starts with the runner's "run:", as KRunner does
// when the person picks it (RunnerManager::run), and waits three seconds for what it starts.
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
    QStringList queries = app.arguments().mid(1);
    const bool run = !queries.isEmpty() && queries.first() == QLatin1String("--run");
    if (run) {
        queries.removeFirst();
    }
    KRunner::RunnerManager manager;
    QJsonObject result;
    for (const QString &query : std::as_const(queries)) {
        QEventLoop loop;
        QObject::connect(&manager, &KRunner::RunnerManager::queryFinished, &loop, &QEventLoop::quit);
        QTimer::singleShot(60000, &loop, &QEventLoop::quit);
        manager.launchQuery(query);
        loop.exec();
        QJsonArray matches;
        const QList<KRunner::QueryMatch> found = manager.matches();
        for (const KRunner::QueryMatch &match : found) {
            matches.append(QJsonArray{match.runner() ? match.runner()->id() : QString(), match.id(), match.text(), match.subtext(), match.relevance()});
        }
        result.insert(query, matches);
        if (run) {
            for (const KRunner::QueryMatch &match : found) {
                if (match.id().contains(QLatin1String("_run:"))) {
                    manager.run(match);
                    QEventLoop wait;
                    QTimer::singleShot(3000, &wait, &QEventLoop::quit);
                    wait.exec();
                    break;
                }
            }
        }
        manager.matchSessionComplete();
    }
    QTextStream(stdout) << QJsonDocument(result).toJson();
    return 0;
}
