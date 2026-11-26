// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
// A proof tool, not installed: prints what the page lists and reads on this system, with the page's own code, as JSON.
// saverstate [--write-ticks]   (--write-ticks: saves the store back as the page's Apply does, to show nothing else changes)
#include "savermodel.h"
#include "showstore.h"

#include <QCoreApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTextStream>

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    SaverModel model;
    model.load(SaverModel::paths());
    ShowStore store = ShowStore::read();
    model.setStore(store.disabled, store.flat);
    if (app.arguments().contains(QStringLiteral("--write-ticks"))) {
        store.disabled = model.disabled();
        store.flat = model.flat();
        store.writeShow();
        store = ShowStore::read();
    }
    QJsonArray savers;
    for (int row = 0; row < model.count(); ++row) {
        savers.append(QJsonObject::fromVariantMap(model.get(row)));
    }
    const QJsonObject out{{QStringLiteral("problem"), model.problem()}, {QStringLiteral("count"), model.count()}, {QStringLiteral("stereo"), model.stereoCount()},
                          {QStringLiteral("flat"), model.flatCount()}, {QStringLiteral("notOffered"), model.notOffered()}, {QStringLiteral("ticked"), model.tickedCount()},
                          {QStringLiteral("showEnabled"), store.enabled}, {QStringLiteral("idleSeconds"), store.idleSeconds}, {QStringLiteral("cycleSeconds"), store.cycleSeconds},
                          {QStringLiteral("disabled"), QJsonArray::fromStringList(store.disabled)}, {QStringLiteral("flatTicked"), QJsonArray::fromStringList(store.flat)},
                          {QStringLiteral("autolock"), store.autolock}, {QStringLiteral("lockMinutes"), store.lockMinutes}, {QStringLiteral("lockKind"), store.lockKind},
                          {QStringLiteral("desktopKinds"), QJsonArray::fromStringList(store.desktopKinds)}, {QStringLiteral("savers"), savers}};
    QTextStream(stdout) << QJsonDocument(out).toJson(QJsonDocument::Compact) << '\n';
    return 0;
}
