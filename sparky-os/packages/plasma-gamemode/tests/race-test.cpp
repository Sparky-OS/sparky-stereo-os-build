// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright 2026 Daniel Campos Ramos
// The applet's GamesModel asks GameMode for its games in reload(). When the service appears while the first answer is
// still on its way, reload() runs twice and both answers arrive. Exit 0: the model ended up not waiting, with the one
// game, after both answers. A crash (SIGSEGV) is the fault.
#include <QCoreApplication>
#include <QDebug>
#include <QElapsedTimer>
#include <QMetaObject>
#include <QThread>
#include <QTimer>

#include "gamesmodel.h"
#include "types.h"

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    Types::registerTypes();

    // The applet's model is made by the QML engine, and its two reloads run inside the event loop: the first from the
    // constructor, the second when the GameMode service appears (QDBusServiceWatcher), before the first answer.
    GamesModel *modelPointer = nullptr;
    int waitingChanges = 0;
    QTimer::singleShot(0, &app, [&] {
        modelPointer = new GamesModel;
        QObject::connect(modelPointer, &GamesModel::waitingChanged, [&] {
            ++waitingChanges;
        });
        // The shell is busy loading the panel: the first answer waits in the event queue when the service appears again.
        QThread::msleep(100);
        QMetaObject::invokeMethod(modelPointer, "reload", Qt::DirectConnection);
        // and the second answer joins it before the loop runs again
        QThread::msleep(300);
    });

    QElapsedTimer clock;
    clock.start();
    int code = 3;
    QTimer poll;
    QObject::connect(&poll, &QTimer::timeout, [&] {
        if (!modelPointer) {
            return;
        }
        GamesModel &model = *modelPointer;
        if (!model.waiting() && model.rowCount() == 1 && clock.elapsed() > 1200) {
            code = 0;
            app.quit();
        } else if (clock.elapsed() > 8000) {
            qWarning("race-test: timeout, waiting=%d rows=%d", model.waiting(), model.rowCount());
            code = 2;
            app.quit();
        }
    });
    poll.start(50);
    app.exec();
    qInfo("race-test: waiting=%d rows=%d waitingChanged=%d", modelPointer->waiting(), modelPointer->rowCount(), waitingChanges);
    return code;
}
