// Created by Daniel Ramos (Capitain Jack) 2026/11/18
// Copyright 2026 under the GNU GPL3 License
#include <QApplication>
#include <QTextStream>
#include <QUrl>
#include <KIO/CopyJob>
#include <KJob>
#include <KUiServerV2JobTracker>

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("copy-default-proof"));
    app.setApplicationDisplayName(QStringLiteral("File copy"));
    app.setDesktopFileName(QStringLiteral("org.kde.dolphin"));
    if (argc != 3) {
        return 2;
    }
    KUiServerV2JobTracker tracker;
    auto job = KIO::copy(QUrl(QString::fromLocal8Bit(argv[1])), QUrl::fromLocalFile(QString::fromLocal8Bit(argv[2])), KIO::HideProgressInfo);
    tracker.registerJob(job);
    QObject::connect(job, &KJob::result, &app, [&app](KJob *finished) {
        QTextStream(stdout) << "copy result " << finished->error() << ' ' << finished->errorString() << Qt::endl;
        app.exit(finished->error() ? 1 : 0);
    });
    return app.exec();
}
