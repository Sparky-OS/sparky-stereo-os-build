// SPDX-License-Identifier: GPL-2.0-or-later
// SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
#include <QCoreApplication>
#include <QGuiApplication>
#include <QWindow>
#include <QTimer>
#include <QFile>
#include <QSaveFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QVariant>
#include <memory>
static void startActionFixture() {
    const auto prefix=qEnvironmentVariable("KAM61_ACTION_CONTROL");
    if(prefix.isEmpty()) return;
    auto *timer=new QTimer(QCoreApplication::instance());
    auto serial=std::make_shared<int>(0);
    QObject::connect(timer,&QTimer::timeout,[prefix,serial] {
        QFile file(prefix+QStringLiteral(".request"));
        if(!file.open(QIODevice::ReadOnly)) return;
        const auto request=QJsonDocument::fromJson(file.readAll()).object();
        const int next=request.value(QStringLiteral("serial")).toInt();
        if(next<=*serial) return;
        QObject *action=nullptr;
        for(auto *window:QGuiApplication::allWindows()) {
            if(request.value(QStringLiteral("recording")).toBool()) {
                for(auto *child:window->findChildren<QObject *>()) {
                    if(child->property("mimes").toString()==QStringLiteral("video/x-matroska") && child->property("checkable").toBool()) { action=child; break; }
                }
            } else action=window->findChild<QObject *>(QStringLiteral("stereo_enable_3d"));
            if(action) break;
        }
        if(!action || !action->property("enabled").toBool()) return;
        const bool inspect=request.value(QStringLiteral("inspect")).toBool();
        const bool desired=request.value(QStringLiteral("checked")).toBool();
        const bool before=action->property("checked").toBool();
        *serial=next; // Consume before invoking: trigger may enter a nested event loop.
        const bool triggered=!inspect && before!=desired;
        const bool invoked=!triggered || QMetaObject::invokeMethod(action,"trigger",Q_ARG(QObject *,nullptr));
        QJsonObject response{{QStringLiteral("serial"),next},{QStringLiteral("before"),before},{QStringLiteral("checked"),action->property("checked").toBool()},{QStringLiteral("invoked"),invoked},{QStringLiteral("inspect"),inspect},{QStringLiteral("desired"),desired},{QStringLiteral("triggered"),triggered}};
        QSaveFile result(prefix+QStringLiteral(".response"));
        if(result.open(QIODevice::WriteOnly)) { result.write(QJsonDocument(response).toJson());result.commit(); }
        QFile journal(prefix+QStringLiteral(".jsonl"));
        if(journal.open(QIODevice::WriteOnly|QIODevice::Append)) journal.write(QJsonDocument(response).toJson(QJsonDocument::Compact)+"\n");
    });
    timer->start(100);
}
Q_COREAPP_STARTUP_FUNCTION(startActionFixture)
